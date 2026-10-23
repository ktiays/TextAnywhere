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
    private var ocrShortcutManager: GlobalShortcutManager?
    private var isCapturingScreen = false

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
            onInsertionStarted: { [weak panelController] in
                panelController?.prepareForInsertion()
            },
            onSuccessfulInsertion: { [weak panelController] in
                panelController?.hide()
            },
            onInsertionFailed: { [weak panelController] in
                panelController?.restoreAfterInsertionFailure()
            },
            onDismiss: { [weak panelController] in
                panelController?.hide()
            },
            onScreenCaptureRequested: { [weak self] in
                self?.recognizeScreenRegion()
            }
        )
        shortcutManager = GlobalShortcutManager(identifier: 1) { [weak self] in
            self?.toggleEditor()
        }
        ocrShortcutManager = GlobalShortcutManager(identifier: 2) { [weak self] in
            self?.recognizeScreenRegion()
        }
    }

    func start() {
        applicationTracker.start()
        do {
            try shortcutManager?.start(shortcut: settings.shortcut)
        } catch {
            session.showError(error.localizedDescription)
        }
        do {
            try applyOCRShortcut()
        } catch {
            session.showError("The OCR shortcut couldn't be registered: \(error.localizedDescription)")
        }
    }

    func toggleEditor() {
        panelController.toggle()
    }

    func showEditor() {
        panelController.show()
    }

    func showEditorWithoutTakingFocus() {
        panelController.showWithoutTakingFocus()
    }

    func updateShortcut(_ shortcut: GlobalShortcut) throws {
        guard let shortcutManager else {
            throw GlobalShortcutError.notStarted
        }
        try shortcutManager.update(shortcut: shortcut)
        settings.shortcut = shortcut
    }

    /// Registers the OCR shortcut while OCR and its shortcut entry are enabled, and releases
    /// it otherwise.
    func applyOCRShortcut() throws {
        guard let ocrShortcutManager else {
            throw GlobalShortcutError.notStarted
        }
        if settings.isOCREnabled && settings.isOCRShortcutEnabled {
            try ocrShortcutManager.start(shortcut: settings.ocrShortcut)
        } else {
            ocrShortcutManager.stop()
        }
    }

    func updateOCRShortcut(_ shortcut: GlobalShortcut) throws {
        guard let ocrShortcutManager else {
            throw GlobalShortcutError.notStarted
        }
        if settings.isOCREnabled && settings.isOCRShortcutEnabled {
            try ocrShortcutManager.start(shortcut: shortcut)
        }
        settings.ocrShortcut = shortcut
    }

    /// Hides the editor while the user selects a screen region, then shows it again with the
    /// recognized text appended to the draft.
    func recognizeScreenRegion() {
        guard !isCapturingScreen else { return }
        let wasEditorVisible = panelController.isVisible
        session.refreshCredentialAvailability()
        guard session.canStartTextRecognition else {
            if !wasEditorVisible {
                panelController.show()
            }
            if !session.isOCRAvailable {
                session.showError(
                    "Enable OCR in Settings and configure \(settings.ocrModel.provider.name) in Settings → Providers."
                )
            }
            return
        }

        isCapturingScreen = true
        panelController.hideForScreenCapture()
        Task { [weak self] in
            let result: Result<Data?, any Error>
            do {
                result = .success(try await ScreenCapture.captureRegion())
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            isCapturingScreen = false

            switch result {
            case .success(nil):
                if wasEditorVisible {
                    panelController.restoreAfterScreenCapture()
                }
            case .success(let imageData?):
                revealEditor(wasVisible: wasEditorVisible)
                session.recognizeText(from: .imageData(imageData))
            case .failure(let error):
                revealEditor(wasVisible: wasEditorVisible)
                session.showError(error.localizedDescription)
            }
        }
    }

    private func revealEditor(wasVisible: Bool) {
        if wasVisible {
            panelController.restoreAfterScreenCapture()
        } else {
            panelController.show()
        }
    }
}
