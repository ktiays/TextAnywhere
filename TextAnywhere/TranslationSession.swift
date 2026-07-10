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
    private var onSuccessfulInsertion: (@MainActor () -> Void)?
    private var onDismiss: (@MainActor () -> Void)?

    private var capturedTarget: CapturedTextTarget?
    private var translationTask: Task<Void, Never>?

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

    var selectedModelID: String {
        settings.modelID(for: settings.selectedProviderID)
    }

    var isTranslating: Bool {
        state == .translating
    }

    var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isTranslating
    }

    var hasAccessibilityPermission: Bool {
        insertionService.isTrusted
    }

    func prepareForPresentation() {
        applicationTracker.refreshRunningApplications()
        if let application = applicationTracker.preferredTargetApplication() {
            selectTarget(application)
        }
        if !isTranslating {
            state = .idle
        }
    }

    func setActions(
        onSuccessfulInsertion: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.onSuccessfulInsertion = onSuccessfulInsertion
        self.onDismiss = onDismiss
    }

    func requestEditorFocus() {
        focusRequestID += 1
    }

    func selectTarget(_ application: TargetApplication) {
        selectedTarget = application
        capturedTarget = insertionService.captureTarget(in: application)
    }

    func requestAccessibilityPermission() {
        insertionService.requestPermission()
    }

    func submit() {
        guard translationTask == nil else { return }

        do {
            let providerID = settings.selectedProviderID
            let provider = Provider.provider(for: providerID)
            let configuration = try providerConfiguration(for: provider)
            let sourceText = draft
            guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderError.invalidConfiguration("Enter text to translate.")
            }
            guard let selectedTarget else {
                throw ProviderError.invalidConfiguration("Choose a target application.")
            }

            if capturedTarget?.application != selectedTarget {
                capturedTarget = insertionService.captureTarget(in: selectedTarget)
            }
            guard let target = capturedTarget else {
                throw ProviderError.invalidConfiguration("Choose a target application.")
            }

            state = .translating
            let targetLanguage = settings.targetLanguage
            translationTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let adapter = adapterFactory(providerID)
                    let translatedText = try await adapter.translate(
                        TranslationRequest(text: sourceText, targetLanguage: targetLanguage),
                        configuration: configuration
                    )
                    try Task.checkCancellation()

                    do {
                        try await insertionService.insert(translatedText, into: target)
                        draft = ""
                        state = .idle
                        translationTask = nil
                        onSuccessfulInsertion?()
                    } catch {
                        pasteboard.copy(translatedText)
                        state = .message(
                            "Automatic insertion failed: \(error.localizedDescription) "
                                + "The translation was copied. Paste it into "
                                + "\(target.application.localizedName) manually.",
                            isError: false
                        )
                        translationTask = nil
                    }
                } catch is CancellationError {
                    state = .idle
                    translationTask = nil
                } catch let error as ProviderError where error == .cancelled {
                    state = .idle
                    translationTask = nil
                } catch {
                    state = .message(error.localizedDescription, isError: true)
                    translationTask = nil
                }
            }
        } catch {
            state = .message(error.localizedDescription, isError: true)
        }
    }

    func cancel() {
        translationTask?.cancel()
        translationTask = nil
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
