//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import Carbon
import XCTest
@testable import TextAnywhere

@MainActor
final class MarkdownTextViewTests: XCTestCase {

    private var textView: MarkdownTextView!
    private var window: NSWindow!
    private var changes: [String] = []
    private var markedTextStates: [Bool] = []
    private let undoManagerProvider = UndoManagerProvider()

    override func setUp() async throws {
        let scrollView = MarkdownTextView.makeScrollView()
        textView = try XCTUnwrap(scrollView.documentView as? MarkdownTextView)
        changes = []
        markedTextStates = []
        textView.onTextChange = { [weak self] text in
            self?.changes.append(text)
        }
        textView.onMarkedTextChange = { [weak self] hasMarkedText in
            self?.markedTextStates.append(hasMarkedText)
        }
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.orderFrontRegardless()
        window.makeKey()
        textView.focus()
        try await waitUntil { self.window.isKeyWindow && self.window.firstResponder === self.textView }
    }

    override func tearDown() async throws {
        window.orderOut(nil)
        window = nil
        textView = nil
    }

    func testUsesTextKit2() {
        XCTAssertNotNil(textView.textLayoutManager)
    }

    func testTypedDashesAndQuotesStayAsTyped() {
        XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticQuoteSubstitutionEnabled)
    }

    func testTypingReportsEachChange() {
        sendKey(characters: "H", keyCode: kVK_ANSI_H, modifiers: .shift)
        sendKey(characters: "i", keyCode: kVK_ANSI_I)

        XCTAssertEqual(textView.string, "Hi")
        XCTAssertEqual(changes, ["H", "Hi"])
    }

    func testNativeKeyEventsTypeAndUndo() {
        useManualUndoGrouping()
        inEvent { textView.updateText("Native ") }
        changes = []

        inEvent { sendKey(characters: "z", keyCode: kVK_ANSI_Z) }
        XCTAssertEqual(textView.string, "Native z")

        sendKey(characters: "z", keyCode: kVK_ANSI_Z, modifiers: .command)
        XCTAssertEqual(textView.string, "Native ")

        // Synthetic ⌘⇧Z events don't match shifted menu key equivalents, so redo directly.
        textView.undoManager?.redo()
        XCTAssertEqual(textView.string, "Native z")
        XCTAssertEqual(changes, ["Native z", "Native ", "Native z"])
    }

    func testExternalUpdatesAreUndoableAndNotReported() {
        useManualUndoGrouping()
        inEvent { textView.updateText("Draft") }
        inEvent { textView.updateText("Draft\nRecognized text") }

        XCTAssertEqual(textView.string, "Draft\nRecognized text")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 21, length: 0))
        XCTAssertTrue(changes.isEmpty)

        sendKey(characters: "z", keyCode: kVK_ANSI_Z, modifiers: .command)
        XCTAssertEqual(textView.string, "Draft")
    }

    func testExternalUpdateKeepsSurroundingTextAndCharacters() {
        useManualUndoGrouping()
        inEvent { textView.updateText("Hello 😀 world") }
        inEvent { textView.updateText("Hello 😃 world") }
        XCTAssertEqual(textView.string, "Hello 😃 world")
        inEvent { textView.updateText("") }
        XCTAssertEqual(textView.string, "")

        sendKey(characters: "z", keyCode: kVK_ANSI_Z, modifiers: .command)
        XCTAssertEqual(textView.string, "Hello 😃 world")
        sendKey(characters: "z", keyCode: kVK_ANSI_Z, modifiers: .command)
        XCTAssertEqual(textView.string, "Hello 😀 world")
    }

    func testReadOnlyIgnoresTypingButAcceptsExternalUpdates() {
        textView.updateText("Draft")
        textView.isEditable = false

        sendKey(characters: "x", keyCode: kVK_ANSI_X)
        XCTAssertEqual(textView.string, "Draft")

        textView.updateText("Translated")
        XCTAssertEqual(textView.string, "Translated")
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(changes.isEmpty)
    }

    func testCompositionIsReportedOnceCommitted() {
        textView.updateText("你好")

        textView.setMarkedText("shi", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        textView.setMarkedText("shij", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(changes.isEmpty)

        textView.insertText("世界", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(textView.string, "你好世界")
        XCTAssertEqual(changes.last, "你好世界")
        XCTAssertEqual(markedTextStates, [true, false])
    }

    func testCancelledCompositionReportsOriginalText() {
        textView.updateText("你好")

        textView.setMarkedText("shi", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        textView.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(textView.string, "你好")
        XCTAssertEqual(changes.last, "你好")
        XCTAssertEqual(markedTextStates, [true, false])
    }

    func testConsumedPasteLeavesTextUnchanged() {
        var pasteCount = 0
        textView.onPaste = {
            pasteCount += 1
            return true
        }
        textView.updateText("Draft")

        textView.paste(nil)

        XCTAssertEqual(pasteCount, 1)
        XCTAssertEqual(textView.string, "Draft")
    }

    func testEscapeCallsHandler() {
        var escapeCount = 0
        textView.onEscape = {
            escapeCount += 1
        }

        sendKey(characters: "\u{1b}", keyCode: kVK_Escape)

        XCTAssertEqual(escapeCount, 1)
    }

    // MARK: - Helpers

    private func sendKey(characters: String, keyCode: Int, modifiers: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: UInt16(keyCode)
            ) else { continue }
            NSApp.sendEvent(event)
        }
    }

    /// The undo manager only closes its per-event group when the outermost run loop finishes a
    /// pass, which never happens while a test runs. Group edits explicitly instead.
    private func useManualUndoGrouping() {
        undoManagerProvider.undoManager.groupsByEvent = false
        textView.delegate = undoManagerProvider
    }

    private func inEvent(_ body: () -> Void) {
        undoManagerProvider.undoManager.beginUndoGrouping()
        body()
        undoManagerProvider.undoManager.endUndoGrouping()
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @escaping () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Condition was not met within \(timeout)")
    }
}

private final class UndoManagerProvider: NSObject, NSTextViewDelegate {

    let undoManager = UndoManager()

    func undoManager(for view: NSTextView) -> UndoManager? {
        undoManager
    }
}
