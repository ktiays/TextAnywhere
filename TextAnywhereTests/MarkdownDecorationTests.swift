//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import XCTest
@testable import TextAnywhere

@available(macOS 27, *)
@MainActor
final class MarkdownDecorationTests: XCTestCase {

    private var textView: MarkdownTextView!
    private var window: NSWindow!
    private var openedLinks: [URL] = []

    override func setUp() async throws {
        let scrollView = MarkdownTextView.makeScrollView()
        textView = try XCTUnwrap(scrollView.documentView as? MarkdownTextView)
        openedLinks = []
        textView.openLink = { [weak self] url in
            self?.openedLinks.append(url)
        }
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.orderFrontRegardless()
        window.makeKey()
        textView.focus()
        textView.rendersMarkdown = true
    }

    override func tearDown() async throws {
        window.orderOut(nil)
        window = nil
        textView = nil
    }

    func testBlocksAreDecoratedBehindTheText() throws {
        setText("- one\n- two\n\n1. first\n\n> quote\n\n```\ncode\n```\n\n---\n\nend")

        let items = try decorationItems()
        XCTAssertEqual(items.filter { if case .bullet = $0 { true } else { false } }.count, 2)
        XCTAssertEqual(items.filter { if case .number("1.", _) = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(items.filter { if case .bar = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(items.filter { if case .background = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(items.filter { if case .rule = $0 { true } else { false } }.count, 1)
        XCTAssertTrue(textView.subviews.first is MarkdownDecorationView)
    }

    func testRevealedMarkersAreNotDecorated() throws {
        setText("- one\n- two", caret: 3)

        let bullets = try decorationItems().filter { if case .bullet = $0 { true } else { false } }
        XCTAssertEqual(bullets.count, 1)
    }

    func testRulesGiveWayToTheirDashesWhenRevealed() throws {
        setText("a\n\n---\n\nb", caret: 4)
        XCTAssertFalse(try decorationItems().contains { if case .rule = $0 { true } else { false } })

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        layout()
        XCTAssertTrue(try decorationItems().contains { if case .rule = $0 { true } else { false } })
    }

    func testClickingACheckboxTogglesTheTaskUndoably() throws {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let provider = DecorationUndoManagerProvider(undoManager: undoManager)
        textView.delegate = provider
        undoManager.beginUndoGrouping()
        setText("- [ ] task\n\nend")
        undoManager.endUndoGrouping()

        let checkbox = try XCTUnwrap(visibleCheckboxes().first)
        XCTAssertEqual(checkbox.state, .off)
        undoManager.beginUndoGrouping()
        checkbox.performClick(nil)
        undoManager.endUndoGrouping()
        XCTAssertEqual(textView.string, "- [x] task\n\nend")

        layout()
        XCTAssertEqual(visibleCheckboxes().first?.state, .on)
        undoManager.undo()
        XCTAssertEqual(textView.string, "- [ ] task\n\nend")
    }

    func testCheckboxesIgnoreClicksWhenReadOnly() throws {
        setText("- [ ] task\n\nend")
        textView.isEditable = false
        layout()

        let checkbox = try XCTUnwrap(visibleCheckboxes().first)
        XCTAssertFalse(checkbox.isEnabled)
        checkbox.performClick(nil)
        XCTAssertEqual(textView.string, "- [ ] task\n\nend")
    }

    func testCommandClickOpensLinks() throws {
        setText("see [docs](https://example.com) and [bad](javascript:alert(1))\n\nend")
        let docs = try XCTUnwrap(point(over: 6))
        let bad = try XCTUnwrap(point(over: 38))

        XCTAssertFalse(handlesClick(at: docs, modifiers: []))
        XCTAssertFalse(handlesClick(at: bad, modifiers: .command))
        XCTAssertTrue(openedLinks.isEmpty)

        textView.mouseDown(with: try XCTUnwrap(mouseDown(at: docs, modifiers: .command)))
        XCTAssertEqual(openedLinks, [URL(string: "https://example.com")!])
    }

    func testCharacterIndexIsNilPastTheEndOfALine() throws {
        setText("short\n\nend")
        let line = try XCTUnwrap(point(over: 2))

        XCTAssertEqual(textView.characterIndex(at: line), 2)
        XCTAssertNil(textView.characterIndex(at: NSPoint(x: 400, y: line.y)))
    }

    // MARK: - Helpers

    private func setText(_ text: String, caret: Int? = nil) {
        textView.string = text
        textView.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        layout()
    }

    private func layout() {
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
    }

    private func decorationItems() throws -> [MarkdownDecorationView.Item] {
        try XCTUnwrap(textView.subviews.first as? MarkdownDecorationView).items
    }

    private func visibleCheckboxes() -> [MarkdownCheckbox] {
        textView.subviews.compactMap { $0 as? MarkdownCheckbox }.filter { !$0.isHidden }
    }

    /// A point over the character at `index` on the first line, found by scanning the line.
    private func point(over index: Int) -> NSPoint? {
        stride(from: CGFloat(0), to: 400, by: 1)
            .map { NSPoint(x: $0, y: 8) }
            .first { textView.characterIndex(at: $0) == index }
    }

    /// Whether the renderer claims a click. Unclaimed clicks would start the text view's own
    /// mouse tracking, which waits for a mouse-up that never comes in a test.
    private func handlesClick(at point: NSPoint, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let event = mouseDown(at: point, modifiers: modifiers) else { return false }
        return textView.renderer?.handleMouseDown(event) ?? false
    }

    private func mouseDown(at point: NSPoint, modifiers: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: textView.convert(point, to: nil),
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }
}

private final class DecorationUndoManagerProvider: NSObject, NSTextViewDelegate {

    let undoManager: UndoManager

    init(undoManager: UndoManager) {
        self.undoManager = undoManager
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        undoManager
    }
}
