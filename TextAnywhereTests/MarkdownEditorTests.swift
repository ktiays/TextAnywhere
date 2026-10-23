//
// Created by ktiays on 2026/10/23.
// Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import Carbon
import WebKit
import XCTest
@testable import TextAnywhere

@MainActor
final class MarkdownEditorTests: XCTestCase {

    private var controller: MarkdownEditorController!
    private var window: NSWindow!
    private var changes: [String] = []

    override func setUp() async throws {
        controller = MarkdownEditorController()
        changes = []
        controller.onChange = { [weak self] markdown in
            self?.changes.append(markdown)
        }
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = controller.webView
        window.orderFrontRegardless()
        window.makeKey()
        try await waitUntil { self.window.isKeyWindow }
        try await waitUntil { try await self.script("return typeof window.markdownEditor") as? String == "object" }
        controller.load("")
        controller.focus()
        try await settle()
    }

    override func tearDown() async throws {
        window.orderOut(nil)
        window = nil
        controller = nil
    }

    func testTypingInsideFormattingKeepsTheCaretAndReportsChanges() async throws {
        try await setMarkdown("Hello **world**", caretAt: (0, 7))

        try await insertText("新")
        try await insertText("的")

        try await assertMarkdown("Hello **w新的orld**")
        XCTAssertEqual(changes.last, "Hello **w新的orld**")
    }

    func testTextAfterClosingDelimiterIsNotFormatted() async throws {
        for character in "**abc** x" {
            try await insertText(String(character))
        }

        try await assertMarkdown("**abc** x")
        let boldText = try await script("return document.querySelector('strong')?.textContent") as? String
        XCTAssertEqual(boldText, "abc")
    }

    func testEnterContinuesListsAndBackspaceDeletes() async throws {
        try await setMarkdown("- one", caretAt: (0, 3))

        try await script("document.execCommand('insertParagraph')")
        try await insertText("two")
        try await script("document.execCommand('delete')")

        try await assertMarkdown("- one\n- tw")
    }

    func testPasteReplacesSelectionAndCopyKeepsMarkdownSource() async throws {
        try await setMarkdown("First\nSecond", caretAt: (0, 2))
        try await script("markdownEditor.setSelection(0, 2, 1, 3)")
        try await script("""
        const data = new DataTransfer();
        data.setData('text/plain', 'X\\nY');
        document.getElementById('editor').dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
        """)
        try await assertMarkdown("FiX\nYond")

        try await setMarkdown("**bold** and _italic_", caretAt: (0, 0))
        try await script("markdownEditor.setSelection(0, 0, 0, 4)")
        let copied = try await script("""
        const data = new DataTransfer();
        document.getElementById('editor').dispatchEvent(new ClipboardEvent('copy', { clipboardData: data, bubbles: true, cancelable: true }));
        return data.getData('text/plain');
        """) as? String
        XCTAssertEqual(copied, "**bold**")
    }

    func testCompositionCommitsOnce() async throws {
        try await setMarkdown("你好", caretAt: (0, 2))

        try await script("""
        const editor = document.getElementById('editor');
        editor.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
        editor.dispatchEvent(new InputEvent('beforeinput', { inputType: 'insertCompositionText', data: '世界', isComposing: true, bubbles: true, cancelable: true }));
        editor.dispatchEvent(new CompositionEvent('compositionend', { data: '世界', bubbles: true }));
        """)

        try await assertMarkdown("你好世界")
        XCTAssertEqual(changes, ["你好世界"])
    }

    func testCheckboxClickTogglesTask() async throws {
        try await setMarkdown("- [ ] task", caretAt: (0, 0))

        try await script("document.querySelector('.md-checkbox').click()")

        try await assertMarkdown("- [x] task")
    }

    func testNativeKeyEventsTypeAndUndo() async throws {
        try await setMarkdown("Native ", caretAt: (0, 7))

        sendKey(characters: "z", keyCode: kVK_ANSI_Z)
        try await waitUntil { try await self.markdown() == "Native z" }

        sendKey(characters: "z", keyCode: kVK_ANSI_Z, modifiers: .command)
        try await waitUntil { try await self.markdown() == "Native " }

        sendKey(characters: "z", keyCode: kVK_ANSI_Z, modifiers: [.command, .shift])
        try await waitUntil { try await self.markdown() == "Native z" }
    }

    func testExternalUpdatesAreUndoable() async throws {
        try await setMarkdown("Draft", caretAt: (0, 5))

        controller.update("Draft\nRecognized text")
        try await waitUntil { try await self.markdown() == "Draft\nRecognized text" }

        sendKey(characters: "z", keyCode: kVK_ANSI_Z, modifiers: .command)
        try await waitUntil { try await self.markdown() == "Draft" }
    }

    func testReadOnlyEditorIgnoresInput() async throws {
        try await setMarkdown("- [ ] task", caretAt: (0, 0))
        controller.setEditable(false)

        try await insertText("bad")
        try await script("document.querySelector('.md-checkbox').click()")

        try await assertMarkdown("- [ ] task")
        XCTAssertTrue(changes.isEmpty)
    }

    // MARK: - Helpers

    private func setMarkdown(_ markdown: String, caretAt caret: (line: Int, offset: Int)) async throws {
        controller.load(markdown)
        controller.focus()
        try await waitUntil { try await self.script("return document.hasFocus()") as? Bool == true }
        try await script(
            "markdownEditor.setSelection(line, offset)",
            arguments: ["line": caret.line, "offset": caret.offset]
        )
        changes = []
    }

    private func insertText(_ text: String) async throws {
        try await script("document.execCommand('insertText', false, text)", arguments: ["text": text])
        try await settle()
    }

    private func assertMarkdown(_ expected: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let actual = try await markdown()
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func markdown() async throws -> String? {
        try await script("return markdownEditor.getMarkdown()") as? String
    }

    @discardableResult
    private func script(_ source: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await controller.webView.callAsyncJavaScript(source, arguments: arguments, in: nil, contentWorld: .page)
    }

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

    /// Lets queued script messages, such as `change`, reach the controller.
    private func settle() async throws {
        try await script("return true")
        try await Task.sleep(for: .milliseconds(30))
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
