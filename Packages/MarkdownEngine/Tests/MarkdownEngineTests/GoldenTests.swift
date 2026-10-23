//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation
import MarkdownEngine
import XCTest

/// Runs the cases in `Golden/cases.json`.
///
/// In `markdown`, `‸` marks the caret and `⁅…⁆` a selection. A rendering writes each styled
/// segment as `«text|tags»`, where the tags list the segment's kinds, `d<n>` for its depth and
/// `hide` when it is concealed. Unstyled text appears as is. A plan's expected result shows the
/// text after the edit with the selection it leaves, or is `null` when no plan applies.
final class GoldenTests: XCTestCase {

    private struct Suite: Decodable {
        let render: [RenderCase]
        let plans: [PlanCase]
    }

    private struct RenderCase: Decodable {
        let name: String
        let markdown: String
        let expected: String
        let mode: String?
    }

    private struct PlanCase: Decodable {
        let name: String
        let action: String
        let markdown: String
        let expected: String?
    }

    private func loadSuite() throws -> Suite {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "cases", withExtension: "json", subdirectory: "Golden"))
        return try JSONDecoder().decode(Suite.self, from: Data(contentsOf: url))
    }

    func testRendering() throws {
        for testCase in try loadSuite().render {
            let (text, selection) = Annotation.parse(testCase.markdown)
            let options = MarkdownOptions()
            options.revealMode = testCase.mode == "line" ? .line : .element
            let engine = MarkdownEngine(text: text, options: options)
            engine.setSelectedRange(selection)
            XCTAssertEqual(Rendering.render(engine), testCase.expected, testCase.name)
        }
    }

    func testPlans() throws {
        for testCase in try loadSuite().plans {
            let (text, selection) = Annotation.parse(testCase.markdown)
            let engine = MarkdownEngine(text: text, options: MarkdownOptions())
            let plan: MarkdownEditPlan? = switch testCase.action {
            case "newline": engine.planForNewline(at: selection)
            case "tab": engine.planForTab(backward: false, range: selection)
            case "backtab": engine.planForTab(backward: true, range: selection)
            case "backspace": engine.planForBackspace(at: selection)
            case "toggleTask": engine.planForTogglingTask(at: selection.location)
            case "bold": engine.planForToggling(.bold, range: selection)
            case "italic": engine.planForToggling(.italic, range: selection)
            case "strikethrough": engine.planForToggling(.strikethrough, range: selection)
            case "code": engine.planForToggling(.code, range: selection)
            default: nil
            }
            guard let plan else {
                XCTAssertNil(testCase.expected, testCase.name)
                continue
            }
            let result = (text as NSString).replacingCharacters(in: plan.replacementRange, with: plan.replacement)
            XCTAssertEqual(Annotation.format(result, selection: plan.selectionAfter), testCase.expected, testCase.name)
        }
    }
}

enum Annotation {

    static func parse(_ markdown: String) -> (String, NSRange) {
        let source = markdown as NSString
        if case let caret = source.range(of: "‸"), caret.location != NSNotFound {
            return (source.replacingCharacters(in: caret, with: ""), NSRange(location: caret.location, length: 0))
        }
        let start = source.range(of: "⁅")
        let end = source.range(of: "⁆")
        guard start.location != NSNotFound, end.location != NSNotFound else {
            return (markdown, NSRange(location: 0, length: 0))
        }
        let text = source.replacingCharacters(in: end, with: "") as NSString
        return (
            text.replacingCharacters(in: start, with: ""),
            NSRange(location: start.location, length: end.location - start.location - 1)
        )
    }

    static func format(_ text: String, selection: NSRange) -> String {
        guard selection.location != NSNotFound else { return text }
        let result = NSMutableString(string: text)
        if selection.length == 0 {
            result.insert("‸", at: selection.location)
        } else {
            result.insert("⁆", at: NSMaxRange(selection))
            result.insert("⁅", at: selection.location)
        }
        return result as String
    }
}

enum Rendering {

    private static let tags: [(MarkdownKind, String)] = [
        (.heading1, "h1"), (.heading2, "h2"), (.heading3, "h3"),
        (.heading4, "h4"), (.heading5, "h5"), (.heading6, "h6"),
        (.strong, "strong"), (.emphasis, "em"), (.strikethrough, "del"), (.codeSpan, "code"),
        (.codeBlock, "pre"), (.link, "link"), (.linkURL, "url"), (.image, "img"),
        (.quote, "quote"), (.listItem, "li"), (.taskItem, "task"), (.taskChecked, "done"),
        (.rule, "hr"), (.table, "table"), (.tableHeader, "th"), (.marker, "mk"),
    ]

    static func render(_ engine: MarkdownEngine) -> String {
        let text = engine.text as NSString
        return engine.segments(in: NSRange(location: 0, length: text.length)).map { segment in
            let content = text.substring(with: segment.range)
            var names = tags.filter { segment.kinds.contains($0.0) }.map(\.1)
            if segment.depth > 0 {
                names.append("d\(segment.depth)")
            }
            if segment.isConcealed {
                names.append("hide")
            }
            return names.isEmpty ? content : "«\(content)|\(names.joined(separator: ","))»"
        }.joined()
    }
}
