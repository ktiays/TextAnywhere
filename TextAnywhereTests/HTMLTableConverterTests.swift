//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import XCTest
@testable import TextAnywhere

final class HTMLTableConverterTests: XCTestCase {

    func testConvertsTableWithFirstRowAsHeader() {
        let html = #"<table border="1"><tr><td>Field</td><td>Content</td></tr><tr><td>activity_type</td><td>Identifiers such as memory.topic</td></tr></table>"#
        XCTAssertEqual(
            HTMLTableConverter.convertingTables(in: html),
            """
            | Field | Content |
            | --- | --- |
            | activity_type | Identifiers such as memory.topic |
            """
        )
    }

    func testSeparatesTableFromSurroundingText() {
        let text = "Intro\n<table><tr><th>A</th></tr><tr><td>1</td></tr></table>\nOutro"
        XCTAssertEqual(
            HTMLTableConverter.convertingTables(in: text),
            "Intro\n\n| A |\n| --- |\n| 1 |\n\nOutro"
        )
    }

    func testCleansCellContent() {
        let html = "<TABLE><TR><TD><b>a</b> &amp; b<br/>c | d &#x4E2D;</TD></TR></TABLE>"
        XCTAssertEqual(
            HTMLTableConverter.convertingTables(in: html),
            "| a & b c \\| d 中 |\n| --- |"
        )
    }

    func testExpandsColumnAndRowSpansIntoEmptyCells() {
        let html = """
            <table>
            <tr><td colspan="2">Merged</td><td>C</td></tr>
            <tr><td rowspan=2>Tall</td><td>B</td><td>C</td></tr>
            <tr><td>B</td><td>C</td></tr>
            </table>
            """
        XCTAssertEqual(
            HTMLTableConverter.convertingTables(in: html),
            """
            | Merged |  | C |
            | --- | --- | --- |
            | Tall | B | C |
            |  | B | C |
            """
        )
    }

    func testPadsShortRows() {
        let html = "<table><tr><td>A</td><td>B</td></tr><tr><td>1</td></tr></table>"
        XCTAssertEqual(
            HTMLTableConverter.convertingTables(in: html),
            "| A | B |\n| --- | --- |\n| 1 |  |"
        )
    }

    func testLeavesUnreadableTablesUnchanged() {
        let nested = "<table><tr><td><table><tr><td>x</td></tr></table></td></tr></table>"
        XCTAssertEqual(HTMLTableConverter.convertingTables(in: nested), nested)
        XCTAssertEqual(HTMLTableConverter.convertingTables(in: "<table></table>"), "<table></table>")
        XCTAssertEqual(HTMLTableConverter.convertingTables(in: "No tables"), "No tables")
    }
}
