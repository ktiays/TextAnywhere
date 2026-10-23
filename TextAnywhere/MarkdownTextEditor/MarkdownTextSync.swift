//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import Carbon
import MarkdownEngine

@available(macOS 27, *)
extension MarkdownTextView {

    /// Whether the text view styles its Markdown source. Turning it off restores plain text.
    /// Either way only attributes change, never the characters.
    var rendersMarkdown: Bool {
        get { renderer is MarkdownTextSync }
        set {
            guard newValue != rendersMarkdown else { return }
            (renderer as? MarkdownTextSync)?.detach()
            renderer = newValue ? MarkdownTextSync(textView: self) : nil
        }
    }
}

/// Keeps a text view's attributes in step with the Markdown engine.
///
/// The text storage delegate is the only source of edits, so typing, pasting, undo, input
/// method commits and programmatic changes all take the same path. While an input method is
/// composing, edits are only noted, and the engine catches up once composition ends.
@available(macOS 27, *)
final class MarkdownTextSync: NSObject, NSTextStorageDelegate, MarkdownTextRendering, MarkdownDecorationSource {

    private static let linkSchemes: Set<String> = ["http", "https", "mailto"]

    private let engine: MarkdownEngine
    private let theme = MarkdownTheme()
    private weak var textView: MarkdownTextView?
    private var decorations: MarkdownDecorations?
    private var needsResynchronization = false
    private var isSelectionUpdateScheduled = false

    init(textView: MarkdownTextView) {
        self.textView = textView
        engine = MarkdownEngine(text: textView.string, options: MarkdownOptions())
        super.init()
        decorations = MarkdownDecorations(textView: textView, source: self)
        engine.setSelectedRange(textView.selectedRange())
        if let storage = textView.textStorage {
            storage.delegate = self
            storage.beginEditing()
            restyle([NSRange(location: 0, length: storage.length)], in: storage)
            storage.endEditing()
        }
        updateTypingAttributes()
    }

    /// The engine's copy of the text, for checking that it matches the text storage.
    var engineText: String {
        engine.text
    }

    func detach() {
        decorations?.remove()
        decorations = nil
        guard let textView, let storage = textView.textStorage else { return }
        storage.delegate = nil
        let range = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        for key in MarkdownTheme.managedKeys {
            storage.removeAttribute(key, range: range)
        }
        storage.addAttributes(theme.plainAttributes, range: range)
        storage.endEditing()
        textView.typingAttributes = theme.plainAttributes
    }

    // MARK: - NSTextStorageDelegate

    // Attributes changed here become part of the edit being processed, before AppKit fixes
    // fonts and before layout is invalidated.
    func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        if textView?.hasMarkedText() == true {
            needsResynchronization = true
            return
        }
        if needsResynchronization {
            resynchronize(textStorage)
            return
        }
        let previousRange = NSRange(location: editedRange.location, length: editedRange.length - delta)
        let replacement = (textStorage.string as NSString).substring(with: editedRange)
        let patch = engine.applyEdit(in: previousRange, replacement: replacement)
        restyle(patch.dirtyRanges.map(\.rangeValue), in: textStorage)
    }

    // MARK: - MarkdownTextRendering

    func selectionDidChange() {
        guard let textView, let storage = textView.textStorage, !textView.hasMarkedText() else { return }
        // Within an editing batch the engine hasn't seen the new text yet; update once it has.
        guard storage.editedMask.isEmpty else {
            scheduleSelectionUpdate()
            return
        }
        if needsResynchronization {
            storage.beginEditing()
            resynchronize(storage)
            storage.endEditing()
        }
        let patch = engine.setSelectedRange(textView.selectedRange())
        if !patch.dirtyRanges.isEmpty {
            storage.beginEditing()
            restyle(patch.dirtyRanges.map(\.rangeValue), in: storage)
            storage.endEditing()
            textView.updateInsertionPointStateAndRestartTimer(true)
        }
        updateTypingAttributes()
    }

    func compositionDidEnd() {
        selectionDidChange()
    }

    /// An input method can leave marked text behind when focus moves away mid-composition.
    /// Commit it, then rebuild the styling if the engine fell out of step.
    func textViewDidBecomeFirstResponder() {
        guard let textView, let storage = textView.textStorage else { return }
        if textView.hasMarkedText() {
            textView.unmarkText()
        }
        if engine.text != storage.string {
            needsResynchronization = true
        }
        selectionDidChange()
    }

    func perform(_ command: Selector) -> Bool {
        guard let textView, textView.isEditable else { return false }
        let selection = textView.selectedRange()
        switch command {
        case #selector(NSResponder.insertNewline(_:)):
            // Shift-Return inserts a plain line break.
            if textView.keyDownModifiers.contains(.shift) {
                return false
            }
            return execute(engine.planForNewline(at: selection))
        case #selector(NSResponder.insertTab(_:)):
            return execute(engine.planForTab(backward: false, range: selection))
        case #selector(NSResponder.insertBacktab(_:)):
            return execute(engine.planForTab(backward: true, range: selection))
        case #selector(NSResponder.deleteBackward(_:)):
            return execute(engine.planForBackspace(at: selection))
        default:
            return false
        }
    }

    func performKeyEquivalent(_ event: NSEvent) -> Bool {
        guard let textView, textView.isEditable,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return false
        }
        let format: MarkdownInlineFormat
        switch Int(event.keyCode) {
        case kVK_ANSI_B:
            format = .bold
        case kVK_ANSI_I:
            format = .italic
        default:
            return false
        }
        _ = execute(engine.planForToggling(format, range: textView.selectedRange()))
        return true
    }

    func handleMouseDown(_ event: NSEvent) -> Bool {
        guard let textView, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let index = textView.characterIndex(at: textView.convert(event.locationInWindow, from: nil)) else {
            return false
        }
        let link = engine.elements(in: NSRange(location: index, length: 0)).last {
            $0.kind == .link && NSLocationInRange(index, $0.range)
        }
        guard let destination = link?.url, let url = URL(string: destination),
              let scheme = url.scheme?.lowercased(), Self.linkSchemes.contains(scheme) else {
            return false
        }
        textView.openLink(url)
        return true
    }

    func viewportWillLayout() {
        decorations?.willLayout()
    }

    func viewportDidLayout(_ fragment: NSTextLayoutFragment) {
        decorations?.add(fragment)
    }

    func viewportDidLayout() {
        decorations?.didLayout()
    }

    // MARK: - MarkdownDecorationSource

    var isSynchronized: Bool {
        !needsResynchronization && textView?.hasMarkedText() != true
    }

    func elements(in range: NSRange) -> [MarkdownElement] {
        engine.elements(in: range)
    }

    func isConcealed(at offset: Int) -> Bool {
        engine.segments(in: NSRange(location: offset, length: 1)).first?.isConcealed ?? false
    }

    func toggleTask(at offset: Int) {
        guard textView?.isEditable == true else { return }
        _ = execute(engine.planForTogglingTask(at: offset))
    }

    // MARK: - Private

    /// Performs a plan as one undoable edit through the text view, like typing would.
    private func execute(_ plan: MarkdownEditPlan?) -> Bool {
        guard let plan, let textView, let storage = textView.textStorage else { return false }
        textView.breakUndoCoalescing()
        guard textView.shouldChangeText(in: plan.replacementRange, replacementString: plan.replacement) else {
            return false
        }
        storage.replaceCharacters(
            in: plan.replacementRange,
            with: NSAttributedString(string: plan.replacement, attributes: textView.typingAttributes)
        )
        textView.didChangeText()
        if plan.selectionAfter.location != NSNotFound {
            textView.setSelectedRange(plan.selectionAfter)
        }
        textView.breakUndoCoalescing()
        textView.scrollRangeToVisible(textView.selectedRange())
        return true
    }

    /// Brings the engine up to date with the text storage by replacing the span that differs.
    private func resynchronize(_ storage: NSTextStorage) {
        needsResynchronization = false
        let current = engine.text as NSString
        let updated = storage.string as NSString
        guard !current.isEqual(to: updated as String) else { return }
        let range = MarkdownTextView.changedRange(from: current, to: updated)
        let replacementLength = range.length + updated.length - current.length
        let replacement = updated.substring(with: NSRange(location: range.location, length: replacementLength))
        let patch = engine.applyEdit(in: range, replacement: replacement)
        restyle(patch.dirtyRanges.map(\.rangeValue), in: storage)
    }

    private func restyle(_ ranges: [NSRange], in storage: NSTextStorage) {
        for range in ranges {
            for segment in engine.segments(in: range) {
                let attributes = theme.attributes(for: segment)
                for key in MarkdownTheme.managedKeys where attributes[key] == nil {
                    storage.removeAttribute(key, range: segment.range)
                }
                storage.addAttributes(attributes, range: segment.range)
            }
        }
    }

    private func scheduleSelectionUpdate() {
        guard !isSelectionUpdateScheduled else { return }
        isSelectionUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.isSelectionUpdateScheduled = false
            self?.selectionDidChange()
        }
    }

    /// New text takes the typing attributes, which AppKit copies from the character before the
    /// caret. After a concealed or dimmed marker that would make it invisible or gray, which
    /// matters for marked text that isn't styled until composition ends.
    private func updateTypingAttributes() {
        guard let textView else { return }
        let location = textView.selectedRange().location
        let probe = NSRange(location: max(location, 1) - 1, length: min(1, engine.length))
        guard let segment = engine.segments(in: probe).first else {
            textView.typingAttributes = theme.plainAttributes
            return
        }
        var kinds = segment.kinds
        kinds.remove([.marker, .linkURL])
        textView.typingAttributes = theme.attributes(kinds: kinds, depth: segment.depth, isConcealed: false)
    }
}
