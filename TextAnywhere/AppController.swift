//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit

@MainActor
final class AppController {

    let settings: AppSettings
    let credentials: any CredentialStore
    let insertionService: any TextInsertionService
    let applicationTracker: ApplicationTracker

    private let pasteboard: any PasteboardWriting

    let session: TranslationSession

    private let panelController: FloatingPanelController
    private var shortcutManager: GlobalShortcutManager?

    convenience init() {
        self.init(
            settings: AppSettings(),
            credentials: KeychainCredentialStore(),
            insertionService: AccessibilityInsertionService(),
            applicationTracker: ApplicationTracker(),
            pasteboard: SystemPasteboardWriter()
        )
    }

    init(
        settings: AppSettings,
        credentials: any CredentialStore,
        insertionService: any TextInsertionService,
        applicationTracker: ApplicationTracker,
        pasteboard: any PasteboardWriting
    ) {
        self.settings = settings
        self.credentials = credentials
        self.insertionService = insertionService
        self.applicationTracker = applicationTracker
        self.pasteboard = pasteboard

        session = TranslationSession(
            settings: settings,
            credentials: credentials,
            insertionService: insertionService,
            pasteboard: pasteboard,
            applicationTracker: applicationTracker,
            adapterFactory: { ProviderAdapterRegistry.adapter(for: $0) }
        )
        panelController = FloatingPanelController(session: session)

        session.setActions(
            onSuccessfulInsertion: { [weak panelController] in
                panelController?.hide()
            },
            onDismiss: { [weak panelController] in
                panelController?.hide()
            }
        )
        shortcutManager = GlobalShortcutManager { [weak self] in
            self?.toggleEditor()
        }
    }

    func start() {
        applicationTracker.start()
        do {
            try shortcutManager?.start(shortcut: settings.shortcut)
        } catch {
            session.showError(error.localizedDescription)
        }
    }

    func toggleEditor() {
        panelController.toggle()
    }

    func showEditor() {
        panelController.show()
    }

    func updateShortcut(_ shortcut: GlobalShortcut) throws {
        guard let shortcutManager else {
            throw GlobalShortcutError.notStarted
        }
        try shortcutManager.update(shortcut: shortcut)
        settings.shortcut = shortcut
    }
}
