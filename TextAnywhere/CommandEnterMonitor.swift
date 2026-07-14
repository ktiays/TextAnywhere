//
//  Created by ktiays on 2026/7/14.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import Carbon
import SwiftUI

struct CommandEnterMonitor: NSViewRepresentable {

    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            hostView: nsView,
            isEnabled: isEnabled,
            action: action
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {

        private weak var hostView: NSView?
        private var eventMonitor: Any?
        private var isEnabled = false
        private var action: (() -> Void)?

        func update(
            hostView: NSView,
            isEnabled: Bool,
            action: @escaping () -> Void
        ) {
            self.hostView = hostView
            self.isEnabled = isEnabled
            self.action = action
            start()
        }

        func stop() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            action = nil
        }

        private func start() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard let self,
                      isEnabled,
                      event.window === hostView?.window,
                      isCommandEnter(event),
                      !hasMarkedText(in: event.window) else {
                    return event
                }

                action?()
                return nil
            }
        }

        private func isCommandEnter(_ event: NSEvent) -> Bool {
            let shortcutModifierMask: NSEvent.ModifierFlags = [
                .command,
                .control,
                .option,
                .shift,
            ]
            let modifiers = event.modifierFlags.intersection(shortcutModifierMask)
            let isEnterKey = event.keyCode == UInt16(kVK_Return)
                || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)
            return modifiers == .command && isEnterKey
        }

        private func hasMarkedText(in window: NSWindow?) -> Bool {
            guard let textView = window?.firstResponder as? NSTextView else { return false }
            return textView.hasMarkedText()
        }
    }
}
