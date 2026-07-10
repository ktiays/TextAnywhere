//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {

    private enum Key {
        static let selectedProvider = "selectedProvider"
        static let targetLanguage = "targetLanguage"
        static let shortcut = "globalShortcut"

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

    var selectedProviderID: ProviderIdentifier {
        didSet {
            defaults.set(selectedProviderID.rawValue, forKey: Key.selectedProvider)
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let providerValue = defaults.string(forKey: Key.selectedProvider)
        selectedProviderID = providerValue.map(ProviderIdentifier.init(rawValue:)) ?? .bailian
        targetLanguageCode = defaults.string(forKey: Key.targetLanguage) ?? TranslationLanguage.english.code

        if let shortcutData = defaults.data(forKey: Key.shortcut),
           let storedShortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: shortcutData) {
            shortcut = storedShortcut
        } else {
            shortcut = .defaultShortcut
        }
    }

    var selectedProvider: Provider {
        Provider.provider(for: selectedProviderID)
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
