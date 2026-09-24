//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation
import Observation

@MainActor
@Observable
final class TranslationSession {

    enum State: Equatable {
        case idle
        case translating
        case message(String, isError: Bool)
    }

    let voiceInput = VoiceInput()
    private var hasBailianAPIKey = false

    var draft = ""
    private(set) var state: State = .idle
    private(set) var selectedTarget: TargetApplication?
    private(set) var focusRequestID = 0

    private let settings: AppSettings
    private let credentials: any CredentialStore
    private let insertionService: any TextInsertionService
    private let pasteboard: any PasteboardWriting
    private let applicationTracker: ApplicationTracker
    private let adapterFactory: (ProviderIdentifier) -> any TranslationProviderAdapter
    private var onInsertionStarted: (@MainActor () -> Void)?
    private var onSuccessfulInsertion: (@MainActor () -> Void)?
    private var onInsertionFailed: (@MainActor () -> Void)?
    private var onDismiss: (@MainActor () -> Void)?

    private var capturedTarget: CapturedTextTarget?
    private var actionTask: Task<Void, Never>?

    init(
        settings: AppSettings,
        credentials: any CredentialStore,
        insertionService: any TextInsertionService,
        pasteboard: any PasteboardWriting,
        applicationTracker: ApplicationTracker,
        adapterFactory: @escaping (ProviderIdentifier) -> any TranslationProviderAdapter
    ) {
        self.settings = settings
        self.credentials = credentials
        self.insertionService = insertionService
        self.pasteboard = pasteboard
        self.applicationTracker = applicationTracker
        self.adapterFactory = adapterFactory
    }

    var runningApplications: [TargetApplication] {
        applicationTracker.runningApplications
    }

    var targetLanguage: TranslationLanguage {
        settings.targetLanguage
    }

    var selectedProvider: Provider {
        settings.selectedProvider
    }

    var enabledProviders: [Provider] {
        settings.enabledProviders
    }

    var selectedModelID: String {
        settings.modelID(for: settings.selectedProviderID)
    }

    func modelID(for provider: Provider) -> String {
        settings.modelID(for: provider.id)
    }

    var isTranslating: Bool {
        state == .translating
    }

    var hasAvailableProvider: Bool {
        settings.isProviderEnabled(settings.selectedProviderID)
    }

    var isTranslationButtonVisible: Bool {
        settings.isTranslationButtonVisible
    }

    var canPaste: Bool {
        hasDraft && actionTask == nil && !voiceInput.isActive
    }

    var canTranslate: Bool {
        hasDraft && hasAvailableProvider && actionTask == nil && !voiceInput.isActive
    }

    var canPerformPrimaryAction: Bool {
        canPerform(settings.primaryButtonAction)
    }

    var primaryButtonTitle: String {
        settings.primaryButtonAction.displayName
    }

    var hasAccessibilityPermission: Bool {
        insertionService.isTrusted
    }

    func prepareForPresentation() {
        refreshVoiceInputAvailability()
        applicationTracker.refreshRunningApplications()
        if let application = applicationTracker.preferredTargetApplication() {
            applicationTracker.refreshRememberedWindow(for: application)
            selectTarget(application)
        }
        if !isTranslating {
            state = .idle
        }
    }

    func setActions(
        onInsertionStarted: @escaping @MainActor () -> Void,
        onSuccessfulInsertion: @escaping @MainActor () -> Void,
        onInsertionFailed: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.onInsertionStarted = onInsertionStarted
        self.onSuccessfulInsertion = onSuccessfulInsertion
        self.onInsertionFailed = onInsertionFailed
        self.onDismiss = onDismiss
    }

    func requestEditorFocus() {
        focusRequestID += 1
    }

    func selectTarget(_ application: TargetApplication) {
        selectedTarget = application
        capturedTarget = capturedTextTarget(for: application)
    }

    func requestAccessibilityPermission() {
        insertionService.requestPermission()
    }

    func selectProvider(_ provider: Provider) {
        guard settings.isProviderEnabled(provider.id) else { return }
        settings.selectedProviderID = provider.id
    }

    func performPrimaryAction() {
        perform(settings.primaryButtonAction)
    }

    private func perform(_ action: EditorAction) {
        switch action {
        case .paste:
            paste()
        case .translateAndPaste:
            translate(thenPaste: true)
        }
    }

    func paste() {
        guard actionTask == nil, !voiceInput.isActive else { return }

        do {
            let sourceText = try sourceText()
            let target = try insertionTarget()
            state = .idle
            actionTask = Task { [weak self] in
                guard let self else { return }
                await insert(
                    sourceText,
                    into: target,
                    copiedContentDescription: "text"
                )
            }
        } catch {
            state = .message(error.localizedDescription, isError: true)
        }
    }

    func translate() {
        translate(thenPaste: false)
    }

    func translateAndPaste() {
        translate(thenPaste: true)
    }

    var isVoiceInputAvailable: Bool {
        settings.isProviderEnabled(.bailian) && hasBailianAPIKey
    }

    func refreshVoiceInputAvailability() {
        let key = (try? credentials.apiKey(for: .bailian)) ?? ""
        hasBailianAPIKey = !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func handleEscape() {
        if voiceInput.isActive {
            voiceInput.cancel()
            requestEditorFocus()
        } else {
            dismiss()
        }
    }

    var canStartVoiceInput: Bool {
        isVoiceInputAvailable && actionTask == nil && !voiceInput.isActive
    }

    func toggleVoiceInput() {
        if voiceInput.phase == .recording {
            voiceInput.finish { [weak self] text in
                guard let self else { return }
                draft += draft.isEmpty ? text : "\n" + text
                state = .idle
                requestEditorFocus()
            } onError: { [weak self] message in
                self?.showError(message)
            }
            return
        }
        guard canStartVoiceInput else { return }
        do {
            let configuration = try TranscriptionConfiguration(
                endpoint: TranscriptionConfiguration.defaultEndpoint,
                model: settings.transcriptionModel,
                apiKey: credentials.apiKey(for: TranscriptionConfiguration.credentialID)
            )
            state = .idle
            voiceInput.start(configuration: configuration, onRecordingLimit: { [weak self] in
                self?.toggleVoiceInput()
            }) { [weak self] message in
                self?.showError(message)
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    func cancel() {
        voiceInput.cancel()
        actionTask?.cancel()
        actionTask = nil
        if isTranslating {
            state = .idle
        }
    }

    func dismiss() {
        cancel()
        onDismiss?()
    }

    func showError(_ message: String) {
        state = .message(message, isError: true)
    }

    private var hasDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func canPerform(_ action: EditorAction) -> Bool {
        switch action {
        case .paste:
            canPaste
        case .translateAndPaste:
            canTranslate
        }
    }

    private func sourceText() throws -> String {
        let sourceText = draft
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.invalidConfiguration("Enter text.")
        }
        return sourceText
    }

    private func insertionTarget() throws -> CapturedTextTarget {
        guard let selectedTarget else {
            throw ProviderError.invalidConfiguration("Choose a target application.")
        }

        if capturedTarget?.application != selectedTarget {
            capturedTarget = capturedTextTarget(for: selectedTarget)
        }
        guard let capturedTarget else {
            throw ProviderError.invalidConfiguration("Choose a target application.")
        }
        return capturedTarget
    }

    private func translate(thenPaste: Bool) {
        guard actionTask == nil, !voiceInput.isActive else { return }

        do {
            let providerID = settings.selectedProviderID
            guard settings.isProviderEnabled(providerID) else {
                throw ProviderError.invalidConfiguration(
                    "Enable a model provider in Settings before translating."
                )
            }
            let provider = Provider.provider(for: providerID)
            let configuration = try providerConfiguration(for: provider)
            let sourceText = try sourceText()
            let target: CapturedTextTarget? = thenPaste ? try insertionTarget() : nil
            state = .translating
            let targetLanguage = settings.targetLanguage
            actionTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let adapter = adapterFactory(providerID)
                    let translatedText = try await adapter.translate(
                        TranslationRequest(text: sourceText, targetLanguage: targetLanguage),
                        configuration: configuration
                    )
                    try Task.checkCancellation()
                    if let target {
                        await insert(
                            translatedText,
                            into: target,
                            copiedContentDescription: "translation"
                        )
                    } else {
                        draft = translatedText
                        state = .idle
                        actionTask = nil
                        requestEditorFocus()
                    }
                } catch is CancellationError {
                    state = .idle
                    actionTask = nil
                } catch let error as ProviderError where error == .cancelled {
                    state = .idle
                    actionTask = nil
                } catch {
                    state = .message(error.localizedDescription, isError: true)
                    actionTask = nil
                }
            }
        } catch {
            state = .message(error.localizedDescription, isError: true)
        }
    }

    private func capturedTextTarget(for application: TargetApplication) -> CapturedTextTarget {
        insertionService.captureTarget(
            in: application,
            window: applicationTracker.rememberedWindow(for: application)
        )
    }

    private func insert(
        _ text: String,
        into target: CapturedTextTarget,
        copiedContentDescription: String
    ) async {
        pasteboard.copy(text)
        onInsertionStarted?()

        do {
            try await insertionService.insert(text, into: target)
            try Task.checkCancellation()
            draft = ""
            state = .idle
            actionTask = nil
            onSuccessfulInsertion?()
        } catch is CancellationError {
            state = .idle
            actionTask = nil
        } catch {
            state = .message(
                "Automatic insertion failed: \(error.localizedDescription) "
                    + "The \(copiedContentDescription) was copied. Paste it into "
                    + "\(target.application.localizedName) manually.",
                isError: true
            )
            actionTask = nil
            onInsertionFailed?()
        }
    }

    private func providerConfiguration(for provider: Provider) throws -> ProviderConfiguration {
        let baseURLValue = settings.baseURL(for: provider.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: baseURLValue),
              let scheme = baseURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw ProviderError.invalidConfiguration("Enter a valid provider base URL.")
        }

        let apiKey: String?
        if provider.requiresAPIKey {
            apiKey = try credentials.apiKey(for: provider.id)
        } else {
            apiKey = nil
        }

        return ProviderConfiguration(
            providerID: provider.id,
            baseURL: baseURL,
            modelID: settings.modelID(for: provider.id),
            apiKey: apiKey,
            thinkingEnabled: settings.thinkingEnabled(for: provider.id)
        )
    }
}
