//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import SwiftUI

struct MarkdownTextEditor: NSViewRepresentable {

    @Binding var text: String
    let isEditable: Bool
    /// Ignored before macOS 27, where the editor always shows plain text.
    let rendersMarkdown: Bool
    /// The editor takes focus when it appears and whenever this value changes.
    let focusRequestID: Int
    let onMarkedTextChange: (Bool) -> Void
    let onPaste: () -> Bool
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MarkdownTextView.makeScrollView()
        if let textView = scrollView.documentView as? MarkdownTextView {
            textView.string = text
            textView.focus()
        }
        context.coordinator.focusRequestID = focusRequestID
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        textView.onTextChange = { text = $0 }
        textView.onMarkedTextChange = onMarkedTextChange
        textView.onPaste = onPaste
        textView.onEscape = onEscape
        if !textView.hasMarkedText() {
            textView.updateText(text)
        }
        textView.isEditable = isEditable
        if #available(macOS 27, *) {
            textView.rendersMarkdown = rendersMarkdown
        }
        if context.coordinator.focusRequestID != focusRequestID {
            context.coordinator.focusRequestID = focusRequestID
            textView.focus()
        }
    }

    final class Coordinator {
        var focusRequestID = 0
    }
}
