//
//  Created by ktiays on 2026/4/15.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

@MainActor
final class PopoverPanelPresenter {

    private var popover: NSPopover?

    func present<Content>(content: Content, relativeTo positioningView: NSView) where Content: View {
        dismiss()

        let hostingController = NSHostingController(rootView: AnyView(content))
        let view = hostingController.view
        view.frame = NSRect(origin: .zero, size: NSSize(width: 1000, height: 1000))
        view.layout()
        let fittingSize = view.fittingSize
        hostingController.preferredContentSize = NSSize(
            width: max(fittingSize.width, 200),
            height: max(fittingSize.height, 100)
        )

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController
        popover.show(
            relativeTo: positioningView.bounds,
            of: positioningView,
            preferredEdge: .minY
        )

        self.popover = popover
    }

    func dismiss() {
        popover?.close()
        popover = nil
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
