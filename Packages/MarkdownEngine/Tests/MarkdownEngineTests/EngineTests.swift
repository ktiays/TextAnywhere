//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation
import MarkdownEngine
import XCTest

final class EngineTests: XCTestCase {

    private func engine(_ text: String) -> MarkdownEngine {
        MarkdownEngine(text: text, options: MarkdownOptions())
    }

    private func elements(_ text: String, kind: MarkdownElementKind) -> [MarkdownElement] {
        let engine = engine(text)
        return engine.elements(in: NSRange(location: 0, length: engine.length)).filter { $0.kind == kind }
    }

    func testLinkElementCarriesItsDestination() throws {
        let link = try XCTUnwrap(elements("see [docs](https://example.com \"Title\") now", kind: .link).first)
        XCTAssertEqual(link.range, NSRange(location: 4, length: 35))
        XCTAssertEqual(link.contentRange, NSRange(location: 5, length: 4))
        XCTAssertEqual(link.markerRange, NSRange(location: 11, length: 19))
        XCTAssertEqual(link.url, "https://example.com")
    }

    func testCodeBlockElementSpansItsFences() throws {
        let text = "a\n\n```swift\nlet a = 1\n```\nb"
        let block = try XCTUnwrap(elements(text, kind: .codeBlock).first)
        XCTAssertEqual(block.range, NSRange(location: 3, length: 22))
        XCTAssertEqual(block.markerRange, NSRange(location: 3, length: 8))
        XCTAssertEqual(block.contentRange, NSRange(location: 12, length: 9))
        XCTAssertEqual(block.language, "swift")
    }

    func testTaskAndListElements() {
        let tasks = elements("- [ ] one\n- [x] two", kind: .task)
        XCTAssertEqual(tasks.map(\.isChecked), [false, true])
        XCTAssertEqual(tasks.map(\.markerRange), [NSRange(location: 2, length: 3), NSRange(location: 12, length: 3)])
        XCTAssertEqual(tasks.map(\.contentRange), [NSRange(location: 6, length: 3), NSRange(location: 16, length: 3)])

        let items = elements("3. a\n4. b\n   - c", kind: .listItem)
        XCTAssertEqual(items.map(\.isOrdered), [true, true, false])
        XCTAssertEqual(items.map(\.ordinal), [3, 4, 0])
        XCTAssertEqual(items.map(\.depth), [0, 0, 1])
        XCTAssertEqual(items[1].range, NSRange(location: 5, length: 11))
        XCTAssertEqual(items[2].markerRange, NSRange(location: 13, length: 1))
    }

    func testQuoteTableAndRuleElements() {
        XCTAssertEqual(elements("> a\n> > b", kind: .quote).map(\.depth), [1, 2])
        XCTAssertEqual(elements("| a | b | c |\n| --- | --- | --- |\n| 1 | 2 | 3 |", kind: .table).map(\.columnCount), [3])
        XCTAssertEqual(elements("a\n\n***\n", kind: .rule).map(\.range), [NSRange(location: 3, length: 3)])
    }

    func testElementsAtAPositionIncludeTheirEnclosingElements() {
        let engine = engine("- a [b](c) d")
        let kinds = engine.elements(in: NSRange(location: 6, length: 0)).map(\.kind)
        XCTAssertEqual(kinds, [.listItem, .link])
    }

    func testClosingDelimiterRestylesTheOpener() {
        let engine = engine("x *a")
        engine.setSelectedRange(NSRange(location: 4, length: 0))
        let patch = engine.applyEdit(in: NSRange(location: 4, length: 0), replacement: "*")
        let dirty = patch.dirtyRanges.map(\.rangeValue)
        XCTAssertEqual(dirty, [NSRange(location: 2, length: 3)])
    }

    func testSelectionChangesReportOnlyRevealedSyntax() {
        let engine = engine("**a** b **c**")
        engine.setSelectedRange(NSRange(location: 6, length: 0))
        let patch = engine.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertEqual(patch.dirtyRanges.map(\.rangeValue), [NSRange(location: 0, length: 2), NSRange(location: 3, length: 2)])
        XCTAssertTrue(engine.setSelectedRange(NSRange(location: 3, length: 0)).dirtyRanges.isEmpty)
    }

    func testOutOfRangeInputIsClamped() {
        let engine = engine("ab")
        engine.applyEdit(in: NSRange(location: 10, length: 5), replacement: "c")
        XCTAssertEqual(engine.text, "abc")
        engine.applyEdit(in: NSRange(location: NSNotFound, length: 0), replacement: "d")
        XCTAssertEqual(engine.text, "abcd")
        XCTAssertEqual(engine.segments(in: NSRange(location: 2, length: 100)).map(\.range), [NSRange(location: 2, length: 2)])
        XCTAssertNil(engine.planForTogglingTask(at: .max))
    }

    func testEmptyDocument() {
        let engine = engine("")
        XCTAssertTrue(engine.segments(in: NSRange(location: 0, length: 0)).isEmpty)
        XCTAssertTrue(engine.elements(in: NSRange(location: 0, length: 0)).isEmpty)
        XCTAssertNil(engine.planForNewline(at: NSRange(location: 0, length: 0)))
        XCTAssertEqual(engine.planForToggling(.bold, range: NSRange(location: 0, length: 0))?.replacement, "****")
    }

    func testLoneSurrogatesDoNotShiftOffsets() {
        let units: [unichar] = [0xD83C] + Array("**a**".utf16)
        let text = NSString(characters: units, length: units.count)
        let engine = MarkdownEngine(text: text as String, options: MarkdownOptions())
        XCTAssertEqual(engine.length, 6)
        let strong = engine.segments(in: NSRange(location: 0, length: 6)).filter { $0.kinds.contains(.strong) }
        XCTAssertEqual(strong.first?.range.location, 1)
    }
}
