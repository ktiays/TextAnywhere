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
    let focusedElement: AXUIElement?
}

protocol TextInsertionService {

    var isTrusted: Bool { get }
    func requestPermission()
    func captureTarget(in application: TargetApplication) -> CapturedTextTarget
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

    func captureTarget(in application: TargetApplication) -> CapturedTextTarget {
        CapturedTextTarget(
            application: application,
            focusedElement: focusedElement(for: application.processIdentifier)
        )
    }

    func insert(_ text: String, into target: CapturedTextTarget) async throws {
        guard isTrusted else {
            throw TextInsertionError.permissionRequired
        }

        if let focusedElement = target.focusedElement,
           tryInsert(text, into: focusedElement) {
            return
        }

        if let currentElement = focusedElement(for: target.application.processIdentifier),
           tryInsert(text, into: currentElement) {
            return
        }

        try await pasteUsingKeyboard(text, into: target.application)
    }

    private func focusedElement(for processIdentifier: pid_t) -> AXUIElement? {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, 1)

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func tryInsert(_ text: String, into element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        )
        guard settableResult == .success, settable.boolValue else { return false }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        return result == .success
    }

    private func pasteUsingKeyboard(
        _ text: String,
        into application: TargetApplication
    ) async throws {
        guard let runningApplication = NSRunningApplication(
            processIdentifier: application.processIdentifier
        ), !runningApplication.isTerminated else {
            throw TextInsertionError.applicationUnavailable
        }

        SystemPasteboardWriter().copy(text)

        if !runningApplication.isActive {
            guard runningApplication.activate(options: [.activateAllWindows]) else {
                throw TextInsertionError.couldNotActivateApplication
            }

            for _ in 0..<10 where !runningApplication.isActive {
                try await Task.sleep(for: .milliseconds(50))
            }
            guard runningApplication.isActive else {
                throw TextInsertionError.couldNotActivateApplication
            }
        }

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

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(application.processIdentifier)
        keyUp.postToPid(application.processIdentifier)
        try await Task.sleep(for: .milliseconds(50))
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
