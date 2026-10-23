//
// Created by ktiays on 2026/10/22.
// Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import SwiftUI

/// A drop target for images and PDFs layered above the text editor. It ignores mouse hit
/// testing, so clicks and text drags still reach the editor underneath.
struct ImageDropTarget: NSViewRepresentable {

    let onTargetChange: (Bool) -> Void
    let onDrop: (OCRSource) -> Void

    func makeNSView(context: Context) -> ImageDropView {
        ImageDropView()
    }

    func updateNSView(_ nsView: ImageDropView, context: Context) {
        nsView.onTargetChange = onTargetChange
        nsView.onDrop = onDrop
    }

    final class ImageDropView: NSView {

        var onTargetChange: ((Bool) -> Void)?
        var onDrop: ((OCRSource) -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes(OCRSource.draggedTypes)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            dragOperation(for: sender)
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            dragOperation(for: sender)
        }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) {
            onTargetChange?(false)
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            onTargetChange?(false)
            guard let source = OCRSource(pasteboard: sender.draggingPasteboard) else { return false }
            onDrop?(source)
            return true
        }

        override func draggingEnded(_ sender: any NSDraggingInfo) {
            onTargetChange?(false)
        }

        private func dragOperation(for sender: any NSDraggingInfo) -> NSDragOperation {
            let isAvailable = OCRSource.isAvailable(in: sender.draggingPasteboard)
            onTargetChange?(isAvailable)
            return isAvailable ? .copy : []
        }
    }
}
