//
//  Created by ktiays on 2026/4/15.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

@MainActor
final class PopoverPanelPresenter: NSObject, NSPopoverDelegate {

    private var popover: NSPopover?
    private var fakePositioningView: NSView?
    private var isClosing = false

    func present<Content>(@ViewBuilder content: () -> Content, relativeTo positioningView: NSView) where Content: View {
        dismiss()
        isClosing = false

        let screenSize = positioningView.window?.screen?.visibleFrame.size ?? .zero

        let hostingController = NSHostingController(rootView: content())
        let idealSize = hostingController.sizeThatFits(in: screenSize)
        let view = hostingController.view
        view.frame = NSRect(origin: .zero, size: idealSize)
        view.layout()
        hostingController.preferredContentSize = idealSize

        let popover = NSPopover()
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = hostingController

        let fakeView = NSView(frame: positioningView.bounds)
        positioningView.addSubview(fakeView)
        self.fakePositioningView = fakeView

        popover.show(relativeTo: fakeView.bounds, of: fakeView, preferredEdge: .minY)

        // Move the fake view off-screen so the arrow disappears.
        fakeView.frame = NSRect(x: 0, y: -1000, width: 1, height: 1)

        self.popover = popover
    }

    func dismiss() {
        guard let popover = popover, !isClosing else { return }
        closeWithAnimation(popover)
    }

    // MARK: - NSPopoverDelegate

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        guard !isClosing else { return false }
        closeWithAnimation(popover)
        return false
    }

    func popoverDidClose(_ notification: Notification) {
        fakePositioningView?.removeFromSuperview()
        fakePositioningView = nil
        popover = nil
        isClosing = false
    }

    private func closeWithAnimation(_ popover: NSPopover) {
        isClosing = true
        guard let window = popover.contentViewController?.view.window, window.alphaValue > 0 else {
            popover.close()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                popover.close()
                self?.isClosing = false
            }
        }
    }
}

private struct PopoverAnchorReader: NSViewRepresentable {

    @Binding var view: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.view = view
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {

    func popoverAnchor(_ view: Binding<NSView?>) -> some View {
        self.background(PopoverAnchorReader(view: view))
    }
}
