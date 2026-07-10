//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let controller = AppController()
    private var statusItem: NSStatusItem?

    private lazy var settingsWindowController = SettingsWindowController(controller: controller)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let didSetActivationPolicy = NSApp.activationPolicy() == .accessory
            || NSApp.setActivationPolicy(.accessory)
        assert(didSetActivationPolicy, "Unable to set accessory activation policy at launch.")

        configureMainMenu()
        updateStatusItemVisibility()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(trayVisibilityDidChange),
            name: AppSettings.trayVisibilityDidChange,
            object: controller.settings
        )
        controller.start()
        controller.showEditorWithoutTakingFocus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        controller.showEditorWithoutTakingFocus()
        return true
    }

    @objc private func showEditor() {
        controller.showEditor()
    }

    @objc private func showSettings() {
        settingsWindowController.showSettings()
    }

    private func configureStatusItem() {
        guard statusItem == nil else { return }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(
            systemSymbolName: "character.cursor.ibeam",
            accessibilityDescription: "TextAnywhere"
        ) {
            image.isTemplate = true
            statusItem.button?.image = image
        }
        statusItem.button?.toolTip = "TextAnywhere"

        let menu = NSMenu()
        menu.addItem(actionItem(title: "Open Editor", action: #selector(showEditor)))
        menu.addItem(
            actionItem(
                title: "Settings…",
                action: #selector(showSettings),
                keyEquivalent: ","
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            actionItem(
                title: "Quit TextAnywhere",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q",
                target: NSApp
            )
        )
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func updateStatusItemVisibility() {
        if controller.settings.isTrayEnabled {
            configureStatusItem()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    @objc private func trayVisibilityDidChange(_ notification: Notification) {
        updateStatusItemVisibility()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(windowMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private func applicationMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem()
        let menu = NSMenu(title: "TextAnywhere")

        menu.addItem(
            actionItem(
                title: "About TextAnywhere",
                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                target: NSApp
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            actionItem(
                title: "Settings…",
                action: #selector(showSettings),
                keyEquivalent: ","
            )
        )
        menu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        menu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        menu.addItem(.separator())
        menu.addItem(
            actionItem(
                title: "Hide TextAnywhere",
                action: #selector(NSApplication.hide(_:)),
                keyEquivalent: "h",
                target: NSApp
            )
        )
        menu.addItem(
            actionItem(
                title: "Hide Others",
                action: #selector(NSApplication.hideOtherApplications(_:)),
                keyEquivalent: "h",
                modifierMask: [.command, .option],
                target: NSApp
            )
        )
        menu.addItem(
            actionItem(
                title: "Show All",
                action: #selector(NSApplication.unhideAllApplications(_:)),
                target: NSApp
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            actionItem(
                title: "Quit TextAnywhere",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q",
                target: NSApp
            )
        )

        menuItem.submenu = menu
        return menuItem
    }

    private func editMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        menu.addItem(responderItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        menu.addItem(
            responderItem(
                title: "Redo",
                action: Selector(("redo:")),
                keyEquivalent: "z",
                modifierMask: [.command, .shift]
            )
        )
        menu.addItem(.separator())
        menu.addItem(responderItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(responderItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(responderItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(
            responderItem(
                title: "Select All",
                action: #selector(NSText.selectAll(_:)),
                keyEquivalent: "a"
            )
        )

        menuItem.submenu = menu
        return menuItem
    }

    private func windowMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem()
        let menu = NSMenu(title: "Window")

        menu.addItem(
            responderItem(
                title: "Close Window",
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            responderItem(
                title: "Minimize",
                action: #selector(NSWindow.performMiniaturize(_:)),
                keyEquivalent: "m"
            )
        )
        menu.addItem(responderItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(
            responderItem(
                title: "Bring All to Front",
                action: #selector(NSApplication.arrangeInFront(_:))
            )
        )

        NSApp.windowsMenu = menu
        menuItem.submenu = menu
        return menuItem
    }

    private func actionItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifierMask
        item.target = target ?? self
        return item
    }

    private func responderItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifierMask
        item.target = nil
        return item
    }
}

@main
private struct TextAnywhereApplication {

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
