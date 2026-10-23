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
    func isConcealed(at offset: Int) -> Bool
    func toggleTask(at offset: Int)
}

/// Draws what replaces concealed block syntax: code block backgrounds, quote bars, rules,
/// list bullets and numbers, and task checkboxes.
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
        case bar(CGRect)
        case rule(CGRect)
        case bullet(CGRect)
        /// An ordered list number, right-aligned in its slot.
        case number(String, CGRect)
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        for item in items {
            switch item {
            case .background(let rect):
                NSColor.quaternarySystemFill.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
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
