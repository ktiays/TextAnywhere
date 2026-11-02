//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import MarkdownEngine

/// What decorations need from the renderer.
@available(macOS 27, *)
protocol MarkdownDecorationSource: AnyObject {
    /// Whether the engine matches the text, so its offsets can be trusted for layout.
    var isSynchronized: Bool { get }
    func elements(in range: NSRange) -> [MarkdownElement]
    /// The visible parts of inline code, with adjacent segments merged.
    func codeSpanRanges(in range: NSRange) -> [NSRange]
    func isConcealed(at offset: Int) -> Bool
    func toggleTask(at offset: Int)
}

/// Draws what replaces concealed syntax: code block and inline code backgrounds, quote bars,
/// rules, list bullets and numbers, and task checkboxes.
///
/// Geometry comes only from the layout fragments that the viewport lays out, so decorations
/// never force layout outside the viewport.
@available(macOS 27, *)
final class MarkdownDecorations: NSObject {

    private struct Fragment {
        let range: NSRange
        let frame: CGRect
        let firstLineFrame: CGRect
    }

    private static let bulletDiameter: CGFloat = 5
    private static let checkboxSize: CGFloat = 16

    private weak var textView: MarkdownTextView?
    private unowned let source: any MarkdownDecorationSource
    private let backgroundView = MarkdownDecorationView()
    private var fragments: [Fragment] = []
    private var checkboxes: [MarkdownCheckbox] = []

    init(textView: MarkdownTextView, source: any MarkdownDecorationSource) {
        self.textView = textView
        self.source = source
        super.init()
        backgroundView.frame = textView.bounds
        backgroundView.autoresizingMask = [.width, .height]
        textView.addSubview(backgroundView, positioned: .below, relativeTo: nil)
    }

    func remove() {
        backgroundView.removeFromSuperview()
        checkboxes.forEach { $0.removeFromSuperview() }
        checkboxes.removeAll()
    }

    func willLayout() {
        fragments.removeAll()
    }

    func add(_ fragment: NSTextLayoutFragment) {
        guard let textView, let contentManager = textView.textLayoutManager?.textContentManager else { return }
        let documentStart = contentManager.documentRange.location
        let start = contentManager.offset(from: documentStart, to: fragment.rangeInElement.location)
        let end = contentManager.offset(from: documentStart, to: fragment.rangeInElement.endLocation)
        let origin = textView.textContainerOrigin
        let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
        let firstLine = fragment.textLineFragments.first?.typographicBounds ?? CGRect(origin: .zero, size: frame.size)
        fragments.append(Fragment(
            range: NSRange(location: start, length: end - start),
            frame: frame,
            firstLineFrame: firstLine.offsetBy(dx: frame.minX, dy: frame.minY)
        ))
    }

    func didLayout() {
        guard let textView, let container = textView.textContainer,
              let first = fragments.first, let last = fragments.last, source.isSynchronized else {
            return
        }
        if textView.subviews.first !== backgroundView {
            textView.addSubview(backgroundView, positioned: .below, relativeTo: nil)
        }

        let padding = container.lineFragmentPadding
        let left = textView.textContainerOrigin.x + padding
        let right = textView.textContainerOrigin.x + container.size.width - padding
        let step = MarkdownTheme.indentStep
        let visibleRange = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)

        var items: [MarkdownDecorationView.Item] = []
        var taskSlots: [(frame: CGRect, element: MarkdownElement)] = []
        for element in source.elements(in: visibleRange) {
            switch element.kind {
            case .codeBlock:
                if let bounds = bounds(of: element.range) {
                    items.append(.background(CGRect(x: left, y: bounds.minY, width: right - left, height: bounds.height)))
                }
            case .quote:
                if let bounds = bounds(of: element.range) {
                    let x = left + CGFloat(element.depth - 1) * step + 2
                    items.append(.bar(CGRect(x: x, y: bounds.minY, width: 3, height: bounds.height)))
                }
            case .rule:
                if let fragment = fragment(containing: element.range.location),
                   source.isConcealed(at: element.range.location) {
                    items.append(.rule(CGRect(x: left, y: fragment.frame.midY.rounded(.down), width: right - left, height: 1)))
                }
            case .listItem, .task:
                guard let fragment = fragment(containing: element.range.location),
                      source.isConcealed(at: element.markerRange.location) else {
                    continue
                }
                let slot = CGRect(
                    x: left + CGFloat(element.depth) * step,
                    y: fragment.firstLineFrame.minY,
                    width: step + (element.kind == .task ? MarkdownTheme.checkboxIndent : 0),
                    height: fragment.firstLineFrame.height
                )
                if element.kind == .task {
                    taskSlots.append((slot, element))
                } else if element.isOrdered {
                    items.append(.number("\(element.ordinal).", slot))
                } else {
                    let diameter = Self.bulletDiameter
                    items.append(.bullet(CGRect(x: slot.midX - diameter / 2, y: slot.midY - diameter / 2, width: diameter, height: diameter)))
                }
            default:
                break
            }
        }
        for range in source.codeSpanRanges(in: visibleRange) {
            let frames = codeSpanFrames(of: range, in: textView)
            if !frames.isEmpty {
                items.append(.codeSpan(frames))
            }
        }
        backgroundView.items = items
        layoutCheckboxes(taskSlots, in: textView)
    }

    private func fragment(containing offset: Int) -> Fragment? {
        fragments.first { NSLocationInRange(offset, $0.range) }
    }

    /// The union of the visible fragments that overlap `range`.
    private func bounds(of range: NSRange) -> CGRect? {
        fragments
            .filter { NSIntersectionRange($0.range, range).length > 0 }
            .map(\.frame)
            .reduce(nil) { union, frame in union?.union(frame) ?? frame }
    }

    /// One frame per line that the code span covers, widened into the padding that the
    /// concealed backticks leave on either side. The code font is smaller than the line's
    /// body text, so each frame is fitted around the code's own glyphs rather than the whole
    /// line, which keeps the code vertically centered in its background.
    private func codeSpanFrames(of range: NSRange, in textView: MarkdownTextView) -> [CGRect] {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let font = textView.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.location),
              let end = contentManager.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else {
            return []
        }
        let origin = textView.textContainerOrigin
        let padding = MarkdownTheme.codeSpanPadding
        var frames: [CGRect] = []
        layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, baseline, _ in
            let baselineY = frame.minY + baseline + origin.y
            frames.append(CGRect(
                x: frame.minX + origin.x - padding,
                y: baselineY - font.ascender - padding / 2,
                width: frame.width + padding * 2,
                height: font.ascender - font.descender + padding
            ))
            return true
        }
        return frames
    }

    private func layoutCheckboxes(_ slots: [(frame: CGRect, element: MarkdownElement)], in textView: MarkdownTextView) {
        while checkboxes.count < slots.count {
            let checkbox = MarkdownCheckbox(checkboxWithTitle: "", target: self, action: #selector(toggle(_:)))
            checkbox.controlSize = .small
            checkbox.refusesFirstResponder = true
            checkbox.setAccessibilityLabel("Task")
            textView.addSubview(checkbox)
            checkboxes.append(checkbox)
        }
        for (index, checkbox) in checkboxes.enumerated() {
            guard index < slots.count else {
                checkbox.isHidden = true
                continue
            }
            let (slot, element) = slots[index]
            let size = Self.checkboxSize
            checkbox.frame = CGRect(x: slot.midX - size / 2, y: slot.midY - size / 2, width: size, height: size)
            checkbox.state = element.isChecked ? .on : .off
            checkbox.markerLocation = element.markerRange.location
            checkbox.isEnabled = textView.isEditable
            checkbox.isHidden = false
        }
    }

    @objc private func toggle(_ sender: MarkdownCheckbox) {
        source.toggleTask(at: sender.markerLocation)
    }
}

@available(macOS 27, *)
final class MarkdownCheckbox: NSButton {

    var markerLocation = 0
}

/// Draws decorations beneath the text and lets every click through to the text view.
@available(macOS 27, *)
final class MarkdownDecorationView: NSView {

    enum Item: Equatable {
        case background(CGRect)
        /// Inline code, with one frame per line it covers.
        case codeSpan([CGRect])
        case bar(CGRect)
        case rule(CGRect)
        case bullet(CGRect)
        /// An ordered list number, right-aligned in its slot.
        case number(String, CGRect)
    }

    /// The quaternary fill that suits code blocks is too faint around short spans of
    /// inline code in dark mode.
    private static let codeSpanFill = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .tertiarySystemFill : .quaternarySystemFill
    }

    var items: [Item] = [] {
        didSet {
            if items != oldValue {
                needsDisplay = true
            }
        }
    }

    override var isFlipped: Bool {
        true
    }

    /// One shape for inline code that wraps across lines, so the lines read as a single
    /// background. Lines that share no horizontal extent can't join and get shapes of their own.
    private static func codeSpanPath(_ frames: [CGRect]) -> NSBezierPath {
        let path = NSBezierPath()
        var lines: [CGRect] = []
        for frame in frames {
            if let last = lines.last,
               !(last.midY < frame.midY && max(last.minX, frame.minX) < min(last.maxX, frame.maxX)) {
                path.append(roundedOutline(of: lines))
                lines.removeAll()
            }
            lines.append(frame)
        }
        if !lines.isEmpty {
            path.append(roundedOutline(of: lines))
        }
        return path
    }

    /// The outline of lines stacked top to bottom, with every corner rounded, including the
    /// inner corners where one line steps out from the next. Adjacent lines are made to meet
    /// halfway, so they neither overlap nor leave a gap.
    private static func roundedOutline(of lines: [CGRect]) -> NSBezierPath {
        var tops = lines.map(\.minY)
        var bottoms = lines.map(\.maxY)
        for index in lines.indices.dropLast() {
            let boundary = (lines[index].maxY + lines[index + 1].minY) / 2
            bottoms[index] = boundary
            tops[index + 1] = boundary
        }

        // Walk down the right edges and back up the left edges.
        var points: [CGPoint] = []
        for index in lines.indices {
            points.append(CGPoint(x: lines[index].maxX, y: tops[index]))
            points.append(CGPoint(x: lines[index].maxX, y: bottoms[index]))
        }
        for index in lines.indices.reversed() {
            points.append(CGPoint(x: lines[index].minX, y: bottoms[index]))
            points.append(CGPoint(x: lines[index].minX, y: tops[index]))
        }

        // Lines with the same edge produce repeated and straight-through points, which aren't corners.
        points = points.enumerated().filter { index, point in point != points[(index + 1) % points.count] }.map(\.element)
        let corners = points.indices.compactMap { index -> CGPoint? in
            let previous = points[(index + points.count - 1) % points.count]
            let point = points[index]
            let next = points[(index + 1) % points.count]
            let isStraight = (previous.x == point.x && point.x == next.x) || (previous.y == point.y && point.y == next.y)
            return isStraight ? nil : point
        }

        let path = NSBezierPath()
        guard let first = corners.first, let last = corners.last else { return path }
        path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for index in corners.indices {
            let previous = corners[(index + corners.count - 1) % corners.count]
            let corner = corners[index]
            let next = corners[(index + 1) % corners.count]
            let radius = min(4, distance(previous, corner) / 2, distance(corner, next) / 2)
            path.appendArc(from: corner, to: next, radius: radius)
        }
        path.close()
        return path
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        for item in items {
            switch item {
            case .background(let rect):
                NSColor.quaternarySystemFill.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            case .codeSpan(let frames):
                Self.codeSpanFill.setFill()
                Self.codeSpanPath(frames).fill()
            case .bar(let rect):
                NSColor.tertiaryLabelColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2).fill()
            case .rule(let rect):
                NSColor.separatorColor.setFill()
                rect.fill()
            case .bullet(let rect):
                NSColor.secondaryLabelColor.setFill()
                NSBezierPath(ovalIn: rect).fill()
            case .number(let text, let slot):
                let number = NSAttributedString(string: text, attributes: [
                    .font: MarkdownTextView.bodyFont,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ])
                let size = number.size()
                number.draw(at: CGPoint(x: slot.maxX - size.width - 4, y: slot.midY - size.height / 2))
            }
        }
    }
}
