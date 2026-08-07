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
        CapturedTextTarget(application: application)
    }

    func insert(_ text: String, into target: CapturedTextTarget) async throws {
        guard isTrusted else {
            throw TextInsertionError.permissionRequired
        }

        try await pasteUsingClipboard(into: target.application)
    }

    private func pasteUsingClipboard(
        into application: TargetApplication
    ) async throws {
        guard let runningApplication = NSRunningApplication(
            processIdentifier: application.processIdentifier
        ), !runningApplication.isTerminated else {
            throw TextInsertionError.applicationUnavailable
        }

        guard runningApplication.activate(options: [.activateAllWindows]) else {
            throw TextInsertionError.couldNotActivateApplication
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
