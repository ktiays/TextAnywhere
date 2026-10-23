//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit

/// Renders Markdown in a `MarkdownTextView` and handles the editing behaviors that come with it.
protocol MarkdownTextRendering: AnyObject {
    func selectionDidChange()
    func compositionDidEnd()
    func textViewDidBecomeFirstResponder()
    /// Returns `true` when it handled a key binding command such as `insertNewline(_:)`.
    func perform(_ command: Selector) -> Bool
    /// Returns `true` when it handled a shortcut such as ⌘B.
    func performKeyEquivalent(_ event: NSEvent) -> Bool
    /// Returns `true` when it handled a click, such as ⌘-clicking a link.
    func handleMouseDown(_ event: NSEvent) -> Bool
    func viewportWillLayout()
    func viewportDidLayout(_ fragment: NSTextLayoutFragment)
    func viewportDidLayout()
}

/// A TextKit 2 text view whose storage always holds the draft's Markdown source.
///
/// Only `textStorage` and `textLayoutManager` may be accessed: reading `layoutManager`
/// silently falls back to TextKit 1.
final class MarkdownTextView: NSTextView {

    static let bodyFont: NSFont = {
        let font = NSFont.preferredFont(forTextStyle: .body)
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }()

    /// Receives the text after each edit, except while an input method is composing.
    var onTextChange: ((String) -> Void)?
    var onMarkedTextChange: ((Bool) -> Void)?
    /// Returns `true` when it consumed the paste, for example by recognizing an image instead.
    var onPaste: (() -> Bool)?
    var onEscape: (() -> Void)?
    var renderer: (any MarkdownTextRendering)?
    var openLink: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// The modifiers of the key press being handled, so commands can tell Shift-Return apart.
    private(set) var keyDownModifiers: NSEvent.ModifierFlags = []

    private var isComposing = false
    private var isUpdatingText = false
    private var focusWhenAttached = false

    /// Creates a text view configured for editing drafts, embedded in a transparent scroll view.
    static func makeScrollView() -> NSScrollView {
        let textView = MarkdownTextView(usingTextLayoutManager: true)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = .zero
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        // The draft is Markdown source: smart dashes would turn the `---` of a horizontal rule
        // into an em dash, and smart quotes would curl quotes in code and link titles.
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.font = bodyFont
        textView.textColor = .textColor

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = textView
        return scrollView
    }

    /// Replaces the text with `text` as one undoable edit. Only the span that differs is
    /// replaced, so appending keeps the existing text, its attributes and the scroll position.
    func updateText(_ text: String) {
        let current = string as NSString
        let updated = text as NSString
        guard !current.isEqual(to: text) else { return }

        let range = Self.changedRange(from: current, to: updated)
        let replacementLength = range.length + updated.length - current.length
        let replacement = updated.substring(with: NSRange(location: range.location, length: replacementLength))
        let wasEditable = isEditable
        isEditable = true
        isUpdatingText = true
        breakUndoCoalescing()
        if shouldChangeText(in: range, replacementString: replacement) {
            textStorage?.replaceCharacters(
                in: range,
                with: NSAttributedString(string: replacement, attributes: typingAttributes)
            )
            didChangeText()
            setSelectedRange(NSRange(location: range.location + replacementLength, length: 0))
            scrollRangeToVisible(selectedRange())
        }
        breakUndoCoalescing()
        isUpdatingText = false
        isEditable = wasEditable
    }

    /// Makes the text view first responder, waiting until it is in a window if necessary.
    func focus() {
        guard let window else {
            focusWhenAttached = true
            return
        }
        window.makeFirstResponder(self)
    }

    /// The range in `old` that must be replaced to produce `new`, widened so that it never
    /// splits a composed character sequence such as a surrogate pair.
    static func changedRange(from old: NSString, to new: NSString) -> NSRange {
        let sharedLength = min(old.length, new.length)
        var prefix = 0
        while prefix < sharedLength && old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }
        if prefix < old.length {
            prefix = old.rangeOfComposedCharacterSequence(at: prefix).location
        }

        var suffix = 0
        while suffix < sharedLength - prefix
            && old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) {
            suffix += 1
        }
        if suffix > 0 {
            let suffixStart = old.length - suffix
            let sequence = old.rangeOfComposedCharacterSequence(at: suffixStart)
            if sequence.location < suffixStart {
                suffix = old.length - NSMaxRange(sequence)
            }
        }
        return NSRange(location: prefix, length: old.length - prefix - suffix)
    }

    private func syncComposingState(textDidChange: Bool) {
        let hasMarkedText = hasMarkedText()
        let didFinishComposing = isComposing && !hasMarkedText
        if hasMarkedText != isComposing {
            isComposing = hasMarkedText
            onMarkedTextChange?(hasMarkedText)
            if didFinishComposing {
                renderer?.compositionDidEnd()
            }
        }
        if !hasMarkedText && !isUpdatingText && (textDidChange || didFinishComposing) {
            onTextChange?(string)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        syncComposingState(textDidChange: true)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        syncComposingState(textDidChange: false)
    }

    override func unmarkText() {
        super.unmarkText()
        syncComposingState(textDidChange: false)
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        if !stillSelectingFlag {
            renderer?.selectionDidChange()
        }
    }

    override func keyDown(with event: NSEvent) {
        keyDownModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        defer { keyDownModifiers = [] }
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        if renderer?.perform(selector) == true {
            return
        }
        super.doCommand(by: selector)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, renderer?.performKeyEquivalent(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            renderer?.textViewDidBecomeFirstResponder()
        }
        return didBecomeFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        if renderer?.handleMouseDown(event) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func textViewportLayoutControllerWillLayout(_ controller: NSTextViewportLayoutController) {
        super.textViewportLayoutControllerWillLayout(controller)
        renderer?.viewportWillLayout()
    }

    override func textViewportLayoutController(
        _ controller: NSTextViewportLayoutController,
        configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment
    ) {
        super.textViewportLayoutController(controller, configureRenderingSurfaceFor: textLayoutFragment)
        renderer?.viewportDidLayout(textLayoutFragment)
    }

    override func textViewportLayoutControllerDidLayout(_ controller: NSTextViewportLayoutController) {
        super.textViewportLayoutControllerDidLayout(controller)
        renderer?.viewportDidLayout()
    }

    /// The character drawn under `point`, in view coordinates, or `nil` when no text is there.
    func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager = textLayoutManager, let contentManager = layoutManager.textContentManager else {
            return nil
        }
        let containerPoint = CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: containerPoint) else { return nil }
        let frame = fragment.layoutFragmentFrame
        let fragmentPoint = CGPoint(x: containerPoint.x - frame.minX, y: containerPoint.y - frame.minY)
        guard let line = fragment.textLineFragments.first(where: { $0.typographicBounds.contains(fragmentPoint) }) else {
            return nil
        }
        let linePoint = CGPoint(
            x: fragmentPoint.x - line.typographicBounds.minX,
            y: fragmentPoint.y - line.typographicBounds.minY
        )
        // The caret index nearest the point lies after the character when the point is in its
        // trailing half.
        var index = line.characterIndex(for: linePoint)
        if index > line.characterRange.location && line.locationForCharacter(at: index).x > linePoint.x {
            index -= 1
        }
        let fragmentStart = contentManager.offset(from: contentManager.documentRange.location, to: fragment.rangeInElement.location)
        return fragmentStart + index
    }

    override func paste(_ sender: Any?) {
        if !hasMarkedText(), onPaste?() == true {
            return
        }
        super.paste(sender)
    }

    override func cancelOperation(_ sender: Any?) {
        guard let onEscape else {
            super.cancelOperation(sender)
            return
        }
        onEscape()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusWhenAttached, let window else { return }
        focusWhenAttached = false
        window.makeFirstResponder(self)
    }
}
