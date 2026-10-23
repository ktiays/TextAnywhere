//
// Created by ktiays on 2026/10/22.
// Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import SwiftUI

/// Intercepts ⌘V in the hosting window so `onPaste` can claim images before the text view
/// receives them. `onPaste` returns `false` to let the regular paste proceed.
struct ImagePasteMonitor: NSViewRepresentable {

    let onPaste: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(hostView: nsView, onPaste: onPaste)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {

        private weak var hostView: NSView?
        private var eventMonitor: Any?
        private var onPaste: (() -> Bool)?

        func update(hostView: NSView, onPaste: @escaping () -> Bool) {
            self.hostView = hostView
            self.onPaste = onPaste
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let window = self.hostView?.window,
                      event.window === window,
                      isCommandV(event),
                      let textInput = window.firstResponder as? NSTextInputClient,
                      !textInput.hasMarkedText(),
                      let onPaste = self.onPaste,
                      onPaste() else {
                    return event
                }
                return nil
            }
        }

        func stop() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            onPaste = nil
        }

        private func isCommandV(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            return modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "v"
        }
    }
}

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
