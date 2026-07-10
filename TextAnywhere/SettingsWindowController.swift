//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private static let contentSize = NSSize(width: 560, height: 420)
    private static let frameAutosaveName = "TextAnywhereSettingsWindow"

    init(controller: AppController) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TextAnywhere Settings"
        window.contentMinSize = Self.contentSize
        window.contentViewController = NSHostingController(
            rootView: SettingsView(controller: controller)
        )
        window.isReleasedWhenClosed = false

        let didRestoreFrame = window.setFrameUsingName(Self.frameAutosaveName)
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !didRestoreFrame {
            window.center()
        }

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSettings() {
        let didSetActivationPolicy = NSApp.activationPolicy() == .regular
            || NSApp.setActivationPolicy(.regular)
        assert(didSetActivationPolicy, "Unable to set regular activation policy for Settings.")

        showWindow(nil)
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  self.window?.isVisible != true,
                  !NSApp.windows.contains(where: { window in
                      window !== self.window && window.isVisible && window.canBecomeMain
                  }) else {
                return
            }

            let didSetActivationPolicy = NSApp.activationPolicy() == .accessory
                || NSApp.setActivationPolicy(.accessory)
            assert(didSetActivationPolicy, "Unable to restore accessory activation policy.")
        }
    }
}
