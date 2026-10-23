//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import MarkdownEngine

/// Maps the engine's semantic kinds to text attributes. Colors are semantic, so styled text
/// follows the appearance without being restyled.
@available(macOS 27, *)
final class MarkdownTheme {

    /// Every attribute the theme sets. Applying a style removes the ones it doesn't use, and
    /// leaves attributes that other parts of the system add untouched.
    static let managedKeys: [NSAttributedString.Key] = [
        .font, .foregroundColor, .kern, .paragraphStyle, .strikethroughStyle, .backgroundColor,
    ]

    private static let headingScales: [(MarkdownKind, CGFloat, NSFont.Weight)] = [
        (.heading1, 1.6, .bold),
        (.heading2, 1.35, .bold),
        (.heading3, 1.18, .bold),
        (.heading4, 1, .semibold),
        (.heading5, 1, .semibold),
        (.heading6, 1, .semibold),
    ]

    private static let monospacedKinds: MarkdownKind = [.codeSpan, .codeBlock, .table]
    static let indentStep: CGFloat = 18
    /// Extra room before a task's text, since a checkbox is wider than a bullet.
    static let checkboxIndent: CGFloat = 4

    private struct StyleKey: Hashable {
        let kinds: UInt32
        let depth: Int
        let isConcealed: Bool
    }

    private let bodyFont = MarkdownTextView.bodyFont
    private var cache: [StyleKey: [NSAttributedString.Key: Any]] = [:]

    func attributes(for segment: MarkdownSegment) -> [NSAttributedString.Key: Any] {
        attributes(kinds: segment.kinds, depth: segment.depth, isConcealed: segment.isConcealed)
    }

    func attributes(kinds: MarkdownKind, depth: Int, isConcealed: Bool) -> [NSAttributedString.Key: Any] {
        let key = StyleKey(kinds: kinds.rawValue, depth: depth, isConcealed: isConcealed)
        if let attributes = cache[key] {
            return attributes
        }
        let attributes = makeAttributes(kinds: kinds, depth: depth, isConcealed: isConcealed)
        cache[key] = attributes
        return attributes
    }

    /// Plain text attributes, used when rendering is turned off.
    var plainAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.textColor]
    }

    private func makeAttributes(kinds: MarkdownKind, depth: Int, isConcealed: Bool) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let paragraphStyle = paragraphStyle(kinds: kinds, depth: depth) {
            attributes[.paragraphStyle] = paragraphStyle
        }
        // A tiny transparent font with negative kerning removes a concealed character's
        // width while keeping it in the text, so offsets always match the source.
        if isConcealed {
            attributes[.font] = NSFont.systemFont(ofSize: 0.01)
            attributes[.foregroundColor] = NSColor.clear
            attributes[.kern] = -0.01
            return attributes
        }

        let font = font(kinds: kinds)
        attributes[.font] = kinds.contains(.emphasis) ? slanted(font) : font
        attributes[.foregroundColor] = color(kinds: kinds)
        if kinds.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if kinds.contains(.codeSpan) {
            attributes[.backgroundColor] = NSColor.quaternarySystemFill
        }
        return attributes
    }

    private func font(kinds: MarkdownKind) -> NSFont {
        var size = bodyFont.pointSize
        var weight = NSFont.Weight.regular
        if let heading = Self.headingScales.first(where: { kinds.contains($0.0) }) {
            size *= heading.1
            weight = heading.2
        }
        if (kinds.contains(.strong) || kinds.contains(.tableHeader)) && weight.rawValue < NSFont.Weight.bold.rawValue {
            weight = .bold
        }
        if !kinds.isDisjoint(with: Self.monospacedKinds) {
            return NSFont.monospacedSystemFont(ofSize: size * 0.92, weight: weight)
        }
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return NSFont(descriptor: descriptor, size: size) ?? font
    }

    /// SF Rounded has no italic, so emphasis shears the upright glyphs. TextKit 2 doesn't draw
    /// the `obliqueness` attribute, so the shear is part of the font.
    private func slanted(_ font: NSFont) -> NSFont {
        let transform = AffineTransform(m11: 1, m12: 0, m21: 0.2, m22: 1, tX: 0, tY: 0)
        return NSFont(descriptor: font.fontDescriptor, textTransform: transform) ?? font
    }

    private func color(kinds: MarkdownKind) -> NSColor {
        if kinds.contains(.marker) {
            return .tertiaryLabelColor
        }
        if kinds.contains(.link) {
            return .linkColor
        }
        if !kinds.isDisjoint(with: [.image, .quote, .taskChecked]) {
            return .secondaryLabelColor
        }
        return .textColor
    }

    /// Lines of a block share one style, since TextKit takes a paragraph's style from its first
    /// character. List markers and quote bars are hidden, so the indentation makes room for
    /// the bullets and bars that decorations draw.
    private func paragraphStyle(kinds: MarkdownKind, depth: Int) -> NSParagraphStyle? {
        let indent: CGFloat
        if kinds.contains(.taskItem) {
            indent = CGFloat(depth + 1) * Self.indentStep + Self.checkboxIndent
        } else if kinds.contains(.listItem) {
            indent = CGFloat(depth + 1) * Self.indentStep
        } else if kinds.contains(.quote) {
            indent = CGFloat(depth) * Self.indentStep
        } else if kinds.contains(.codeBlock) {
            indent = Self.indentStep / 2
        } else {
            return nil
        }
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        return style
    }
}
