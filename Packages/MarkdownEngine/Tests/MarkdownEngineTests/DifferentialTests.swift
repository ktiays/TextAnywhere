//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation
import MarkdownEngine
import XCTest

/// Applies random edits and selection changes, restyling only what each patch reports, and
/// checks that the result always equals styling the whole document from scratch.
final class DifferentialTests: XCTestCase {

    private struct Style: Equatable {
        let kinds: UInt32
        let depth: Int
        let isConcealed: Bool
    }

    private struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }

        mutating func next(below bound: Int) -> Int {
            bound <= 0 ? 0 : Int(next() % UInt64(bound))
        }
    }

    private static let fragments = [
        "**", "*", "_", "~~", "`", "```", "\n", "\n\n", "# ", "## ", "- ", "- [ ] ", "- [x] ", "1. ", "> ",
        "[", "](", ")", "![", "|", " | ", "| --- |", "---", "===", "a", "bc", "word ", "你好", "🌏", "\\",
        " ", "  ", "*️⃣", "\r\n", "<", ">", "https://e.com", "&amp;", "\t",
    ]

    private func randomText(_ generator: inout Generator, maximumFragments: Int) -> String {
        (0..<generator.next(below: maximumFragments + 1))
            .map { _ in Self.fragments[generator.next(below: Self.fragments.count)] }
            .joined()
    }

    private func randomRange(_ generator: inout Generator, length: Int, maximumLength: Int) -> NSRange {
        let location = generator.next(below: length + 1)
        return NSRange(location: location, length: generator.next(below: min(maximumLength, length - location) + 1))
    }

    private func styles(_ engine: MarkdownEngine) -> [Style?] {
        var result: [Style?] = []
        for segment in engine.segments(in: NSRange(location: 0, length: engine.length)) {
            XCTAssertEqual(segment.range.location, result.count, "Segments must cover the document without gaps")
            result += Array(repeating: style(segment), count: segment.range.length)
        }
        XCTAssertEqual(result.count, engine.length)
        return result
    }

    private func style(_ segment: MarkdownSegment) -> Style {
        Style(kinds: segment.kinds.rawValue, depth: segment.depth, isConcealed: segment.isConcealed)
    }

    private func apply(_ patch: MarkdownPatch, from engine: MarkdownEngine, to shadow: inout [Style?]) {
        for value in patch.dirtyRanges {
            for segment in engine.segments(in: value.rangeValue) {
                for offset in segment.range.location..<NSMaxRange(segment.range) {
                    shadow[offset] = style(segment)
                }
            }
        }
    }

    private func fresh(_ text: String, selection: NSRange) -> MarkdownEngine {
        let engine = MarkdownEngine(text: text, options: MarkdownOptions())
        engine.setSelectedRange(selection)
        return engine
    }

    /// Where `offset` lands after `range` is replaced by `insertedLength` units, as the engine maps it.
    private func map(_ offset: Int, through range: NSRange, insertedLength: Int) -> Int {
        if offset <= range.location {
            return offset
        }
        if offset >= NSMaxRange(range) {
            return offset - range.length + insertedLength
        }
        return range.location + insertedLength
    }

    func testIncrementalPatchesMatchFullRestyling() {
        var generator = Generator(state: 0x5EED)
        for document in 0..<300 {
            var text = randomText(&generator, maximumFragments: 12)
            let engine = MarkdownEngine(text: text, options: MarkdownOptions())
            var selection = NSRange(location: 0, length: 0)
            var shadow = styles(engine)
            for step in 0..<25 {
                let length = (text as NSString).length
                let range = randomRange(&generator, length: length, maximumLength: 6)
                let replacement = randomText(&generator, maximumFragments: 3)
                let insertedLength = (replacement as NSString).length

                let patch = engine.applyEdit(in: range, replacement: replacement)
                text = (text as NSString).replacingCharacters(in: range, with: replacement)
                shadow.replaceSubrange(
                    range.location..<NSMaxRange(range),
                    with: Array(repeating: nil, count: insertedLength)
                )
                apply(patch, from: engine, to: &shadow)
                let start = map(selection.location, through: range, insertedLength: insertedLength)
                let end = max(map(NSMaxRange(selection), through: range, insertedLength: insertedLength), start)
                selection = NSRange(location: start, length: end - start)

                let context = "document \(document), step \(step): \(text.debugDescription)"
                XCTAssertEqual(engine.text, text, context)
                guard shadow == styles(fresh(text, selection: selection)) else {
                    XCTFail("Edit patch missed a change in \(context)")
                    return
                }

                selection = randomRange(&generator, length: (text as NSString).length, maximumLength: 8)
                apply(engine.setSelectedRange(selection), from: engine, to: &shadow)
                guard shadow == styles(fresh(text, selection: selection)) else {
                    XCTFail("Selection patch missed a change in \(context)")
                    return
                }
            }
        }
    }
}
