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
    private var isPresentedBinding: Binding<Bool>?

    func present<Content>(@ViewBuilder content: () -> Content, relativeTo positioningView: NSView, isPresented: Binding<Bool>? = nil) where Content: View {
        dismiss()
        isClosing = false
        isPresentedBinding = isPresented

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
        self.popover = nil
        isClosing = false
        isPresentedBinding?.wrappedValue = false
        isPresentedBinding = nil
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

private struct PopoverPanelModifier<PopoverContent: View>: ViewModifier {

    @Binding var isPresented: Bool
    @ViewBuilder let popoverContent: () -> PopoverContent

    @State private var presenter = PopoverPanelPresenter()
    @State private var anchorView: NSView?

    func body(content: Content) -> some View {
        content
            .background(PopoverAnchorReader(view: $anchorView))
            .onChange(of: isPresented) {
                updatePresentation()
            }
            .onChange(of: anchorView) {
                updatePresentation()
            }
    }

    private func updatePresentation() {
        if isPresented, let anchorView {
            presenter.present(content: popoverContent, relativeTo: anchorView, isPresented: $isPresented)
        } else if !isPresented {
            presenter.dismiss()
        }
    }
}

extension View {

    func popoverAnchor(_ view: Binding<NSView?>) -> some View {
        self.background(PopoverAnchorReader(view: view))
    }

    func popoverPanel<Content>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View where Content: View {
        modifier(PopoverPanelModifier(isPresented: isPresented, popoverContent: content))
    }
}
