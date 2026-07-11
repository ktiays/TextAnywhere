//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import SwiftUI

private final class FloatingEditorPanel: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {

    private let session: TranslationSession

    private lazy var panel: FloatingEditorPanel = {
        let panel = FloatingEditorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 280),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        installCloseButton(in: panel)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.minSize = NSSize(width: 420, height: 480)
        panel.contentViewController = NSHostingController(rootView: ContentView(session: session))
        panel.delegate = self
        panel._cornerRadius = closeButtonPadding + min(closeButtonSize.width, closeButtonSize.height) / 2
        return panel
    }()

    init(session: TranslationSession) {
        self.session = session
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        show(takingFocus: true)
    }

    func showWithoutTakingFocus() {
        show(takingFocus: false)
    }

    private func show(takingFocus: Bool) {
        session.prepareForPresentation()
        positionPanel()
        panel.orderFrontRegardless()
        guard takingFocus else { return }

        panel.makeKey()
        DispatchQueue.main.async { [weak self] in
            self?.session.requestEditorFocus()
        }
    }

    func hide() {
        session.cancel()
        panel.orderOut(nil)
    }

    func prepareForInsertion() {
        panel.orderOut(nil)
    }

    func restoreAfterInsertionFailure() {
        positionPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        DispatchQueue.main.async { [weak self] in
            self?.session.requestEditorFocus()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    @objc private func closePanel() {
        hide()
    }
    
    private let closeButtonSize: CGSize = .init(width: 28, height: 28)
    private let closeButtonPadding: CGFloat = 12

    private func installCloseButton(in panel: NSPanel) {
        guard let systemCloseButton = panel.standardWindowButton(.closeButton),
              let titlebarView = systemCloseButton.superview else {
            return
        }

        let closeButton = NSButton(title: "", target: self, action: #selector(closePanel))
        if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
            let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            closeButton.image = image.withSymbolConfiguration(configuration)
            closeButton.imagePosition = .imageOnly
        }
        closeButton.bezelStyle = .glass
        closeButton.borderShape = .circle
        closeButton.controlSize = .small
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.toolTip = "Close"
        closeButton.setAccessibilityLabel("Close")
        closeButton.refusesFirstResponder = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        titlebarView.addSubview(closeButton, positioned: .above, relativeTo: systemCloseButton)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: titlebarView.leadingAnchor, constant: closeButtonPadding),
            closeButton.topAnchor.constraint(equalTo: titlebarView.topAnchor, constant: closeButtonPadding),
            closeButton.widthAnchor.constraint(equalToConstant: closeButtonSize.width),
            closeButton.heightAnchor.constraint(equalToConstant: closeButtonSize.height),
        ])
        systemCloseButton.isHidden = true
    }

    private func positionPanel() {
        let pointerLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointerLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }

        let panelSize = panel.frame.size
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)
        let origin = NSPoint(
            x: min(max(pointerLocation.x - panelSize.width / 2, visibleFrame.minX), maximumX),
            y: min(max(pointerLocation.y - panelSize.height / 2, visibleFrame.minY), maximumY)
        )
        panel.setFrameOrigin(origin)
    }
}
