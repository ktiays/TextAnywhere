//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import Carbon

struct GlobalShortcut: Codable, Equatable, Sendable {

    let keyCode: UInt32
    let modifiers: UInt32
    let keyDisplayName: String

    static let defaultShortcut = GlobalShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey),
        keyDisplayName: "Space"
    )

    static let defaultOCRShortcut = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_O),
        modifiers: UInt32(controlKey | optionKey),
        keyDisplayName: "O"
    )

    var displayName: String {
        var components: [String] = []
        if modifiers & UInt32(controlKey) != 0 { components.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { components.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { components.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { components.append("⌘") }
        components.append(keyDisplayName)
        return components.joined()
    }

    init(event: NSEvent) throws {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }

        guard carbonModifiers != 0 else {
            throw GlobalShortcutError.modifierRequired
        }

        keyCode = UInt32(event.keyCode)
        modifiers = carbonModifiers
        keyDisplayName = Self.displayName(for: event)
    }

    init(keyCode: UInt32, modifiers: UInt32, keyDisplayName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyDisplayName = keyDisplayName
    }

    private static func displayName(for event: NSEvent) -> String {
        if event.keyCode == UInt16(kVK_Space) { return "Space" }
        if event.keyCode == UInt16(kVK_Return) { return "Return" }
        if event.keyCode == UInt16(kVK_Tab) { return "Tab" }
        if event.keyCode == UInt16(kVK_Delete) { return "Delete" }
        if event.keyCode == UInt16(kVK_ForwardDelete) { return "Forward Delete" }
        if event.keyCode == UInt16(kVK_Escape) { return "Escape" }
        return event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
    }
}

@MainActor
final class GlobalShortcutManager {

    private static let signature: OSType = 0x5458414E

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var registeredShortcut: GlobalShortcut?
    private let identifier: UInt32
    private let action: @MainActor () -> Void

    /// Each manager needs a distinct `identifier`, because every manager's handler receives
    /// the hot key events of the whole application.
    init(identifier: UInt32, action: @escaping @MainActor () -> Void) {
        self.identifier = identifier
        self.action = action
    }

    deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func start(shortcut: GlobalShortcut) throws {
        if eventHandler == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                    var hotKeyID = EventHotKeyID()
                    let status = GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )
                    guard status == noErr else { return OSStatus(eventNotHandledErr) }
                    let manager = Unmanaged<GlobalShortcutManager>
                        .fromOpaque(userData)
                        .takeUnretainedValue()
                    return MainActor.assumeIsolated {
                        guard hotKeyID.signature == GlobalShortcutManager.signature,
                              hotKeyID.id == manager.identifier else {
                            return OSStatus(eventNotHandledErr)
                        }
                        manager.action()
                        return noErr
                    }
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
            guard status == noErr else {
                throw GlobalShortcutError.registrationFailed(status)
            }
        }
        try update(shortcut: shortcut)
    }

    func stop() {
        guard let hotKey else { return }
        UnregisterEventHotKey(hotKey)
        self.hotKey = nil
        registeredShortcut = nil
    }

    func update(shortcut: GlobalShortcut) throws {
        let previousShortcut = registeredShortcut
        stop()

        do {
            try register(shortcut)
        } catch {
            if let previousShortcut {
                try? register(previousShortcut)
            }
            throw error
        }
    }

    private func register(_ shortcut: GlobalShortcut) throws {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &reference
        )
        guard status == noErr, let reference else {
            throw GlobalShortcutError.registrationFailed(status)
        }
        hotKey = reference
        registeredShortcut = shortcut
    }
}

enum GlobalShortcutError: LocalizedError {

    case modifierRequired
    case notStarted
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .modifierRequired:
            "The shortcut must include Command, Control, Option, or Shift."
        case .notStarted:
            "The global shortcut manager is not ready."
        case .registrationFailed:
            "That shortcut is already in use."
        }
    }
}
