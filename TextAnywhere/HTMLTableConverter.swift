//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation

/// Rewrites HTML `<table>` markup, which the Markdown editor shows as plain text, as GFM pipe
/// tables. The first row becomes the header row. Tables that can't be read as rows of cells,
/// such as nested tables, are left unchanged.
enum HTMLTableConverter {

    static func convertingTables(in text: String) -> String {
        let tablePattern = #/<table\b[^>]*>(.*?)</table\s*>/#
            .ignoresCase()
            .dotMatchesNewlines()
        var result = ""
        var remainder = text[...]
        while let match = remainder.firstMatch(of: tablePattern) {
            result += remainder[..<match.range.lowerBound]
            remainder = remainder[match.range.upperBound...]
            guard let table = pipeTable(from: match.output.1) else {
                result += match.output.0
                continue
            }
            appendBlankLineSeparator(to: &result)
            result += table
            if !remainder.isEmpty && !remainder.hasPrefix("\n\n") {
                result += remainder.hasPrefix("\n") ? "\n" : "\n\n"
            }
        }
        result += remainder
        return result
    }

    private static func appendBlankLineSeparator(to text: inout String) {
        guard !text.isEmpty, !text.hasSuffix("\n\n") else { return }
        text += text.hasSuffix("\n") ? "\n" : "\n\n"
    }

    private static func pipeTable(from content: Substring) -> String? {
        guard content.firstMatch(of: #/<table\b/#.ignoresCase()) == nil else { return nil }

        let rowPattern = #/<tr\b[^>]*>(.*?)</tr\s*>/#
            .ignoresCase()
            .dotMatchesNewlines()
        let cellPattern = #/<t[dh]\b([^>]*)>(.*?)</t[dh]\s*>/#
            .ignoresCase()
            .dotMatchesNewlines()

        // Maps a column index to the number of following rows a `rowspan` cell still covers.
        var rowSpans: [Int: Int] = [:]
        var rows: [[String]] = []
        for rowMatch in content.matches(of: rowPattern) {
            var row: [String] = []
            for cellMatch in rowMatch.output.1.matches(of: cellPattern) {
                appendSpannedCells(to: &row, rowSpans: &rowSpans)
                let attributes = cellMatch.output.1
                let columnSpan = span(named: "colspan", in: attributes)
                let rowSpan = span(named: "rowspan", in: attributes)
                for offset in 0..<columnSpan {
                    if rowSpan > 1 {
                        rowSpans[row.count] = rowSpan - 1
                    }
                    row.append(offset == 0 ? cellText(from: cellMatch.output.2) : "")
                }
            }
            for column in rowSpans.keys where column >= row.count {
                decrementRowSpan(at: column, in: &rowSpans)
            }
            if !row.isEmpty {
                rows.append(row)
            }
        }

        guard let header = rows.first,
              let columnCount = rows.map(\.count).max() else { return nil }
        let lines = [formattedRow(header, columnCount: columnCount)]
            + [formattedRow(Array(repeating: "---", count: columnCount), columnCount: columnCount)]
            + rows.dropFirst().map { formattedRow($0, columnCount: columnCount) }
        return lines.joined(separator: "\n")
    }

    /// Fills the columns that cells from earlier rows cover with `rowspan`.
    private static func appendSpannedCells(to row: inout [String], rowSpans: inout [Int: Int]) {
        while rowSpans[row.count] != nil {
            decrementRowSpan(at: row.count, in: &rowSpans)
            row.append("")
        }
    }

    private static func decrementRowSpan(at column: Int, in rowSpans: inout [Int: Int]) {
        guard let remaining = rowSpans[column] else { return }
        rowSpans[column] = remaining > 1 ? remaining - 1 : nil
    }

    private static func span(named name: String, in attributes: Substring) -> Int {
        let attributePattern = #/([A-Za-z-]+)\s*=\s*["']?(\d+)/#
        for match in attributes.matches(of: attributePattern) where match.output.1.lowercased() == name {
            return min(max(Int(match.output.2) ?? 1, 1), 100)
        }
        return 1
    }

    private static func formattedRow(_ cells: [String], columnCount: Int) -> String {
        let paddedCells = cells + Array(repeating: "", count: columnCount - cells.count)
        return "| " + paddedCells.joined(separator: " | ") + " |"
    }

    private static func cellText(from html: Substring) -> String {
        let text = String(html)
            .replacing(#/<br\s*/?>/#.ignoresCase(), with: " ")
            .replacing(#/<[^>]*>/#, with: "")
        return decodingEntities(in: text)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .replacing("|", with: "\\|")
    }

    private static func decodingEntities(in text: String) -> String {
        let namedEntities: [Substring: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        ]
        return text.replacing(#/&(#[xX][0-9A-Fa-f]+|#[0-9]+|[A-Za-z]+);/#) { match in
            let entity = match.output.1
            let scalarValue: UInt32? = if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                UInt32(entity.dropFirst(2), radix: 16)
            } else if entity.hasPrefix("#") {
                UInt32(entity.dropFirst())
            } else {
                nil
            }
            if let scalarValue, let scalar = Unicode.Scalar(scalarValue) {
                return String(Character(scalar))
            }
            return namedEntities[entity] ?? String(match.output.0)
        }
    }
}
