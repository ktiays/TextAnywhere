//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

struct CapturedTextTarget {

    let application: TargetApplication
    let window: TargetWindow?
}

protocol TextInsertionService {

    var isTrusted: Bool { get }
    func requestPermission()
    func captureTarget(in application: TargetApplication, window: TargetWindow?) -> CapturedTextTarget
    func insert(_ text: String, into target: CapturedTextTarget) async throws
}

struct AccessibilityInsertionService: TextInsertionService {

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func captureTarget(in application: TargetApplication, window: TargetWindow?) -> CapturedTextTarget {
        CapturedTextTarget(application: application, window: window)
    }

    func insert(_ text: String, into target: CapturedTextTarget) async throws {
        guard isTrusted else {
            throw TextInsertionError.permissionRequired
        }

        try await pasteUsingClipboard(into: target.application, window: target.window)
    }

    private func pasteUsingClipboard(
        into application: TargetApplication,
        window: TargetWindow?
    ) async throws {
        guard let runningApplication = NSRunningApplication(
            processIdentifier: application.processIdentifier
        ), !runningApplication.isTerminated else {
            throw TextInsertionError.applicationUnavailable
        }

        let didFocusRememberedWindow = window?.raise() == true
        if NSApp.isActive {
            NSApp.yieldActivation(to: runningApplication)
        }
        if didFocusRememberedWindow {
            runningApplication.activate()
        } else {
            runningApplication.activate(options: [.activateAllWindows])
        }

        for _ in 0..<10 where !runningApplication.isActive {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard runningApplication.isActive else {
            throw TextInsertionError.couldNotActivateApplication
        }
        try await Task.sleep(for: .milliseconds(50))
        try Task.checkCancellation()

        guard let eventSource = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              ) else {
            throw TextInsertionError.couldNotCreatePasteEvent
        }

        eventSource.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        // Include device-specific state so Command is handled like a physical modifier key.
        let commandFlags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
        keyDown.flags = commandFlags
        keyUp.flags = commandFlags
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        try await Task.sleep(for: .milliseconds(100))
    }
}

extension TargetWindow {

    var isValid: Bool {
        copyAttributeValue(kAXRoleAttribute as String) != nil
    }

    static func currentlyFocused(in processIdentifier: pid_t) -> TargetWindow? {
        let application = AXUIElementCreateApplication(processIdentifier)
        let element = copyElement(from: application, attribute: kAXFocusedWindowAttribute as String)
            ?? copyElement(from: application, attribute: kAXMainWindowAttribute as String)
        guard let element else { return nil }
        return TargetWindow(processIdentifier: processIdentifier, element: element)
    }

    @discardableResult
    func raise() -> Bool {
        guard isValid else { return false }

        if isMinimized {
            AXUIElementSetAttributeValue(
                element,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
        }

        let mainResult = AXUIElementSetAttributeValue(
            element,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        let raiseResult = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        return mainResult == .success || raiseResult == .success
    }

    private var isMinimized: Bool {
        guard let value = copyAttributeValue(kAXMinimizedAttribute as String),
              CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return false
        }
        return CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self))
    }

    private func copyAttributeValue(_ attribute: String) -> CFTypeRef? {
        Self.copyAttributeValue(from: element, attribute: attribute)
    }

    private static func copyElement(from element: AXUIElement, attribute: String) -> AXUIElement? {
        guard let value = copyAttributeValue(from: element, attribute: attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func copyAttributeValue(from element: AXUIElement, attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }
}

enum TextInsertionError: LocalizedError {

    case permissionRequired
    case unsupportedTextElement
    case applicationUnavailable
    case couldNotActivateApplication
    case couldNotCreatePasteEvent

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            "Accessibility permission is required to insert text directly."
        case .unsupportedTextElement:
            "The selected app does not expose a writable text selection."
        case .applicationUnavailable:
            "The selected app is no longer running."
        case .couldNotActivateApplication:
            "The selected app could not be focused for automatic paste."
        case .couldNotCreatePasteEvent:
            "The automatic paste keyboard event could not be created."
        }
    }
}

protocol PasteboardWriting {

    func copy(_ text: String)
}

struct SystemPasteboardWriter: PasteboardWriting {

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
