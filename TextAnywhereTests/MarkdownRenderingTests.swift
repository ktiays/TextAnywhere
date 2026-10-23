//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import Carbon
import XCTest
@testable import TextAnywhere

@available(macOS 27, *)
@MainActor
final class MarkdownRenderingTests: XCTestCase {

    private var textView: MarkdownTextView!
    private var window: NSWindow!
    private let undoManagerProvider = RenderingUndoManagerProvider()

    override func setUp() async throws {
        let scrollView = MarkdownTextView.makeScrollView()
        textView = try XCTUnwrap(scrollView.documentView as? MarkdownTextView)
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
        textView.rendersMarkdown = true
        try await waitUntil { self.window.isKeyWindow && self.window.firstResponder === self.textView }
    }

    override func tearDown() async throws {
        window.orderOut(nil)
        window = nil
        textView = nil
    }

    func testMarkersAreConcealedAwayFromTheCaret() {
        setText("a **bold** z‸")

        XCTAssertTrue(isConcealed(at: 2))
        XCTAssertTrue(isConcealed(at: 8))
        XCTAssertTrue(font(at: 4).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(font(at: 0).pointSize, MarkdownTextView.bodyFont.pointSize)
    }

    func testMovingTheCaretRevealsAndConcealsMarkers() {
        setText("a **bold** z‸")

        textView.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertFalse(isConcealed(at: 2))
        XCTAssertEqual(color(at: 2), .tertiaryLabelColor)

        textView.setSelectedRange(NSRange(location: 12, length: 0))
        XCTAssertTrue(isConcealed(at: 2))
    }

    func testTypingAClosingDelimiterStylesTheOpener() {
        setText("x *a‸")
        XCTAssertEqual(font(at: 3).textTransform.m21, 0)

        sendKey(characters: "*", keyCode: kVK_ANSI_8, modifiers: .shift)

        XCTAssertEqual(textView.string, "x *a*")
        XCTAssertEqual(color(at: 2), .tertiaryLabelColor)
        XCTAssertGreaterThan(font(at: 3).textTransform.m21, 0)
    }

    func testReturnContinuesAndEndsLists() {
        setText("- one‸")

        sendKey(characters: "\r", keyCode: kVK_Return)
        XCTAssertEqual(textView.string, "- one\n- ")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 8, length: 0))

        sendKey(characters: "\r", keyCode: kVK_Return)
        XCTAssertEqual(textView.string, "- one\n")
    }

    func testShiftReturnInsertsAPlainLineBreak() {
        setText("- one‸")

        sendKey(characters: "\r", keyCode: kVK_Return, modifiers: .shift)

        XCTAssertEqual(textView.string, "- one\n")
    }

    func testTabIndentsAndShiftTabOutdentsListItems() {
        setText("- a\n- b‸")

        sendKey(characters: "\t", keyCode: kVK_Tab)
        XCTAssertEqual(textView.string, "- a\n  - b")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))

        sendKey(characters: "\u{19}", keyCode: kVK_Tab, modifiers: .shift)
        XCTAssertEqual(textView.string, "- a\n- b")
    }

    func testBackspaceAfterAListMarkerRemovesIt() {
        setText("- a\n- ‸b")

        sendKey(characters: "\u{7f}", keyCode: kVK_Delete)

        XCTAssertEqual(textView.string, "- a\nb")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testCommandBTogglesBold() {
        setText("hello world‸")
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        sendKey(characters: "b", keyCode: kVK_ANSI_B, modifiers: .command)
        XCTAssertEqual(textView.string, "**hello** world")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 5))

        sendKey(characters: "b", keyCode: kVK_ANSI_B, modifiers: .command)
        XCTAssertEqual(textView.string, "hello world")
    }

    func testEditPlansAreUndoable() {
        useManualUndoGrouping()
        inEvent { setText("- one‸") }

        inEvent { sendKey(characters: "\r", keyCode: kVK_Return) }
        XCTAssertEqual(textView.string, "- one\n- ")

        sendKey(characters: "z", keyCode: kVK_ANSI_Z, modifiers: .command)
        XCTAssertEqual(textView.string, "- one")
        XCTAssertEqual(engineText(), "- one")
        XCTAssertEqual(color(at: 0), .tertiaryLabelColor)
    }

    func testCompositionIsStyledOnceCommitted() {
        setText("**a** ‸")

        textView.setMarkedText("b", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(isConcealed(at: 6))
        XCTAssertNotEqual(engineText(), textView.string)

        textView.insertText("不", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(textView.string, "**a** 不")
        XCTAssertEqual(engineText(), textView.string)
        XCTAssertTrue(isConcealed(at: 0))
    }

    func testRegainingFocusCommitsAbandonedComposition() {
        setText("text‸")
        textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))

        window.makeFirstResponder(nil)
        textView.focus()

        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertEqual(engineText(), textView.string)
    }

    func testExternalUpdatesAreStyled() {
        setText("‸")

        textView.updateText("# Title")

        XCTAssertEqual(font(at: 3).pointSize, MarkdownTextView.bodyFont.pointSize * 1.6, accuracy: 0.01)
        XCTAssertEqual(engineText(), "# Title")
    }

    func testTurningRenderingOffRestoresPlainText() {
        setText("# **Title**‸")

        textView.rendersMarkdown = false

        XCTAssertEqual(textView.string, "# **Title**")
        for offset in 0..<(textView.string as NSString).length {
            XCTAssertEqual(font(at: offset), MarkdownTextView.bodyFont)
            XCTAssertEqual(color(at: offset), .textColor)
        }
    }

    /// Restyling only what patches report must match styling the same text from scratch.
    func testIncrementalStylingMatchesFullStyling() {
        let fragments = ["**", "*", "`", "```\n", "\n", "# ", "- ", "- [ ] ", "> ", "[a](b)", "| x |", "word ", "你好", "🌏", "\\"]
        var generator = SeededGenerator(state: 0x7E57)
        for _ in 0..<40 {
            setText("‸")
            for _ in 0..<15 {
                let length = (textView.string as NSString).length
                let location = Int.random(in: 0...length, using: &generator)
                // Text views never edit inside a character, which would make AppKit fall back to
                // a font that sticks once the character is whole again.
                let range = (textView.string as NSString).rangeOfComposedCharacterSequences(
                    for: NSRange(location: location, length: Int.random(in: 0...min(3, length - location), using: &generator))
                )
                let replacement = (0..<Int.random(in: 0...2, using: &generator))
                    .map { _ in fragments.randomElement(using: &generator)! }
                    .joined()
                textView.insertText(replacement, replacementRange: range)
                let newLength = (textView.string as NSString).length
                let caret = (textView.string as NSString).rangeOfComposedCharacterSequences(
                    for: NSRange(location: Int.random(in: 0...newLength, using: &generator), length: 0)
                ).location
                textView.setSelectedRange(NSRange(location: caret, length: 0))
                guard assertMatchesFreshStyling() else { return }
            }
        }
    }

    // MARK: - Helpers

    private func setText(_ annotated: String) {
        let caret = (annotated as NSString).range(of: "‸")
        textView.string = (annotated as NSString).replacingCharacters(in: caret, with: "")
        textView.setSelectedRange(NSRange(location: caret.location, length: 0))
    }

    private func engineText() -> String? {
        (textView.renderer as? MarkdownTextSync)?.engineText
    }

    private func font(at offset: Int) -> NSFont {
        textView.textStorage?.attribute(.font, at: offset, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 0)
    }

    private func color(at offset: Int) -> NSColor? {
        textView.textStorage?.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
    }

    private func isConcealed(at offset: Int) -> Bool {
        font(at: offset).pointSize < 1
    }

    private func assertMatchesFreshStyling(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let fresh = MarkdownTextView(usingTextLayoutManager: true)
        fresh.font = MarkdownTextView.bodyFont
        fresh.string = textView.string
        fresh.setSelectedRange(textView.selectedRange())
        fresh.rendersMarkdown = true
        guard let storage = textView.textStorage, let expected = fresh.textStorage else { return false }
        XCTAssertEqual(engineText(), textView.string, file: file, line: line)
        let range = NSRange(location: 0, length: storage.length)
        storage.fixAttributes(in: range)
        expected.fixAttributes(in: range)
        for offset in 0..<storage.length {
            for key in MarkdownTheme.managedKeys {
                let actual = storage.attribute(key, at: offset, effectiveRange: nil) as? NSObject
                let wanted = expected.attribute(key, at: offset, effectiveRange: nil) as? NSObject
                if !isEquivalent(actual, wanted) {
                    XCTFail("\(key.rawValue) differs at \(offset) in \(textView.string.debugDescription): \(String(describing: actual)) instead of \(String(describing: wanted))", file: file, line: line)
                    return false
                }
            }
        }
        return true
    }

    /// Font substitution can produce distinct but identical font objects depending on the
    /// fonts a character had before, so fonts compare by name and size.
    private func isEquivalent(_ actual: NSObject?, _ expected: NSObject?) -> Bool {
        if let actual = actual as? NSFont, let expected = expected as? NSFont {
            return actual.fontName == expected.fontName && actual.pointSize == expected.pointSize
        }
        return actual == expected
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

private final class RenderingUndoManagerProvider: NSObject, NSTextViewDelegate {

    let undoManager = UndoManager()

    func undoManager(for view: NSTextView) -> UndoManager? {
        undoManager
    }
}

private struct SeededGenerator: RandomNumberGenerator {

    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
