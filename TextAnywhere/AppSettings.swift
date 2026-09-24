//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {

    static let trayVisibilityDidChange = Notification.Name(
        "AppSettings.trayVisibilityDidChange"
    )

    private enum Key {
        static let selectedProvider = "selectedProvider"
        static let enabledProviders = "enabledProviders"
        static let targetLanguage = "targetLanguage"
        static let shortcut = "globalShortcut"
        static let trayEnabled = "trayEnabled"
        static let translationButtonVisible = "translationButtonVisible"
        static let primaryButtonAction = "primaryButtonAction"

        static func baseURL(_ providerID: ProviderIdentifier) -> String {
            "provider.\(providerID.rawValue).baseURL"
        }

        static func modelID(_ providerID: ProviderIdentifier) -> String {
            "provider.\(providerID.rawValue).modelID"
        }

        static func cachedModels(_ providerID: ProviderIdentifier) -> String {
            "provider.\(providerID.rawValue).cachedModels"
        }

        static func thinkingEnabled(_ providerID: ProviderIdentifier) -> String {
            "provider.\(providerID.rawValue).thinkingEnabled"
        }
    }

    private let defaults: UserDefaults

    var transcriptionModel: String {
        didSet { defaults.set(transcriptionModel, forKey: "transcriptionModel") }
    }

    var selectedProviderID: ProviderIdentifier {
        didSet {
            defaults.set(selectedProviderID.rawValue, forKey: Key.selectedProvider)
        }
    }

    private(set) var enabledProviderIDs: Set<ProviderIdentifier> {
        didSet {
            defaults.set(
                enabledProviderIDs.map(\.rawValue).sorted(),
                forKey: Key.enabledProviders
            )
        }
    }

    var targetLanguageCode: String {
        didSet {
            defaults.set(targetLanguageCode, forKey: Key.targetLanguage)
        }
    }

    var shortcut: GlobalShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) {
                defaults.set(data, forKey: Key.shortcut)
            }
        }
    }

    var isTrayEnabled: Bool {
        didSet {
            defaults.set(isTrayEnabled, forKey: Key.trayEnabled)
            guard isTrayEnabled != oldValue else { return }
            NotificationCenter.default.post(
                name: Self.trayVisibilityDidChange,
                object: self
            )
        }
    }

    var isTranslationButtonVisible: Bool {
        didSet {
            defaults.set(isTranslationButtonVisible, forKey: Key.translationButtonVisible)
        }
    }

    var primaryButtonAction: EditorAction {
        didSet {
            defaults.set(primaryButtonAction.rawValue, forKey: Key.primaryButtonAction)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        transcriptionModel = defaults.string(forKey: "transcriptionModel") ?? TranscriptionConfiguration.defaultModel

        let providerValue = defaults.string(forKey: Key.selectedProvider)
        let initialProviderID = providerValue.map(ProviderIdentifier.init(rawValue:)) ?? .bailian
        selectedProviderID = initialProviderID
        if let enabledProviderValues = defaults.stringArray(forKey: Key.enabledProviders) {
            enabledProviderIDs = Set(
                enabledProviderValues.map(ProviderIdentifier.init(rawValue:))
            )
        } else {
            enabledProviderIDs = [initialProviderID]
        }
        targetLanguageCode = defaults.string(forKey: Key.targetLanguage) ?? TranslationLanguage.english.code

        if let shortcutData = defaults.data(forKey: Key.shortcut),
           let storedShortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: shortcutData) {
            shortcut = storedShortcut
        } else {
            shortcut = .defaultShortcut
        }
        isTrayEnabled = defaults.object(forKey: Key.trayEnabled) as? Bool ?? true
        isTranslationButtonVisible = defaults.object(forKey: Key.translationButtonVisible) as? Bool ?? true
        primaryButtonAction = defaults.string(forKey: Key.primaryButtonAction)
            .flatMap(EditorAction.init(rawValue:))
            ?? .translateAndPaste
    }

    var selectedProvider: Provider {
        Provider.provider(for: selectedProviderID)
    }

    var enabledProviders: [Provider] {
        Provider.presets.filter { enabledProviderIDs.contains($0.id) }
    }

    var targetLanguage: TranslationLanguage {
        TranslationLanguage.language(for: targetLanguageCode)
    }

    func baseURL(for providerID: ProviderIdentifier) -> String {
        defaults.string(forKey: Key.baseURL(providerID))
            ?? Provider.provider(for: providerID).defaultBaseURL
    }

    func setBaseURL(_ baseURL: String, for providerID: ProviderIdentifier) {
        defaults.set(baseURL, forKey: Key.baseURL(providerID))
    }

    func modelID(for providerID: ProviderIdentifier) -> String {
        defaults.string(forKey: Key.modelID(providerID))
            ?? Provider.provider(for: providerID).defaultModelID
    }

    func setModelID(_ modelID: String, for providerID: ProviderIdentifier) {
        defaults.set(modelID, forKey: Key.modelID(providerID))
    }

    func thinkingEnabled(for providerID: ProviderIdentifier) -> Bool {
        defaults.bool(forKey: Key.thinkingEnabled(providerID))
    }

    func setThinkingEnabled(_ isEnabled: Bool, for providerID: ProviderIdentifier) {
        defaults.set(isEnabled, forKey: Key.thinkingEnabled(providerID))
    }

    func isProviderEnabled(_ providerID: ProviderIdentifier) -> Bool {
        enabledProviderIDs.contains(providerID)
    }

    func setProviderEnabled(_ isEnabled: Bool, for providerID: ProviderIdentifier) {
        if isEnabled {
            let shouldSelectProvider = enabledProviderIDs.isEmpty
                || !enabledProviderIDs.contains(selectedProviderID)
            enabledProviderIDs.insert(providerID)
            if shouldSelectProvider {
                selectedProviderID = providerID
            }
            return
        }

        enabledProviderIDs.remove(providerID)
        if selectedProviderID == providerID,
           let fallbackProvider = enabledProviders.first {
            selectedProviderID = fallbackProvider.id
        }
    }

    func cachedModels(for providerID: ProviderIdentifier) -> [ModelDescriptor] {
        guard let data = defaults.data(forKey: Key.cachedModels(providerID)) else {
            return []
        }
        return (try? JSONDecoder().decode([ModelDescriptor].self, from: data)) ?? []
    }

    func setCachedModels(_ models: [ModelDescriptor], for providerID: ProviderIdentifier) {
        guard let data = try? JSONEncoder().encode(models) else { return }
        defaults.set(data, forKey: Key.cachedModels(providerID))
    }
}
