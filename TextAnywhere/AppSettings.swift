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
        static let legacyTargetLanguage = "targetLanguage"
        static let primaryLanguage = "primaryLanguage"
        static let secondaryLanguage = "secondaryLanguage"
        static let targetLanguageMode = "targetLanguageMode"
        static let shortcut = "globalShortcut"
        static let trayEnabled = "trayEnabled"
        static let translationButtonVisible = "translationButtonVisible"
        static let primaryButtonAction = "primaryButtonAction"
        static let ocrEnabled = "ocrEnabled"
        static let ocrModel = "ocrModel"
        static let ocrMode = "ocrMode"
        static let ocrScreenCaptureEnabled = "ocrScreenCaptureEnabled"
        static let ocrPasteAndDropEnabled = "ocrPasteAndDropEnabled"
        static let ocrFilePickerEnabled = "ocrFilePickerEnabled"
        static let ocrShortcutEnabled = "ocrShortcutEnabled"
        static let ocrShortcut = "ocrShortcut"

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

    private(set) var primaryLanguageCode: String {
        didSet {
            defaults.set(primaryLanguageCode, forKey: Key.primaryLanguage)
        }
    }

    private(set) var secondaryLanguageCode: String {
        didSet {
            defaults.set(secondaryLanguageCode, forKey: Key.secondaryLanguage)
        }
    }

    var targetLanguageMode: TargetLanguageMode {
        didSet {
            defaults.set(targetLanguageMode.rawValue, forKey: Key.targetLanguageMode)
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

    var isOCREnabled: Bool {
        didSet {
            defaults.set(isOCREnabled, forKey: Key.ocrEnabled)
        }
    }

    var ocrModel: OCRModel {
        didSet {
            defaults.set(ocrModel.rawValue, forKey: Key.ocrModel)
        }
    }

    var ocrMode: OCRMode {
        didSet {
            defaults.set(ocrMode.rawValue, forKey: Key.ocrMode)
        }
    }

    var isOCRScreenCaptureEnabled: Bool {
        didSet {
            defaults.set(isOCRScreenCaptureEnabled, forKey: Key.ocrScreenCaptureEnabled)
        }
    }

    var isOCRPasteAndDropEnabled: Bool {
        didSet {
            defaults.set(isOCRPasteAndDropEnabled, forKey: Key.ocrPasteAndDropEnabled)
        }
    }

    var isOCRFilePickerEnabled: Bool {
        didSet {
            defaults.set(isOCRFilePickerEnabled, forKey: Key.ocrFilePickerEnabled)
        }
    }

    var isOCRShortcutEnabled: Bool {
        didSet {
            defaults.set(isOCRShortcutEnabled, forKey: Key.ocrShortcutEnabled)
        }
    }

    var ocrShortcut: GlobalShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(ocrShortcut) {
                defaults.set(data, forKey: Key.ocrShortcut)
            }
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
        let initialPrimaryLanguageCode = defaults.string(forKey: Key.primaryLanguage)
            ?? defaults.string(forKey: Key.legacyTargetLanguage)
            ?? TranslationLanguage.english.code
        primaryLanguageCode = initialPrimaryLanguageCode
        secondaryLanguageCode = defaults.string(forKey: Key.secondaryLanguage)
            ?? Self.defaultSecondaryLanguageCode(differentFrom: initialPrimaryLanguageCode)
        targetLanguageMode = defaults.string(forKey: Key.targetLanguageMode)
            .flatMap(TargetLanguageMode.init(rawValue:))
            ?? .automatic

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
        isOCREnabled = defaults.object(forKey: Key.ocrEnabled) as? Bool ?? true
        ocrModel = defaults.string(forKey: Key.ocrModel)
            .flatMap(OCRModel.init(rawValue:))
            ?? .glmOCR
        ocrMode = defaults.string(forKey: Key.ocrMode)
            .flatMap(OCRMode.init(rawValue:))
            ?? .recognizeOnly
        isOCRScreenCaptureEnabled = defaults.object(forKey: Key.ocrScreenCaptureEnabled) as? Bool ?? true
        isOCRPasteAndDropEnabled = defaults.object(forKey: Key.ocrPasteAndDropEnabled) as? Bool ?? true
        isOCRFilePickerEnabled = defaults.object(forKey: Key.ocrFilePickerEnabled) as? Bool ?? true
        isOCRShortcutEnabled = defaults.object(forKey: Key.ocrShortcutEnabled) as? Bool ?? false
        if let shortcutData = defaults.data(forKey: Key.ocrShortcut),
           let storedShortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: shortcutData) {
            ocrShortcut = storedShortcut
        } else {
            ocrShortcut = .defaultOCRShortcut
        }
    }

    var selectedProvider: Provider {
        Provider.provider(for: selectedProviderID)
    }

    var enabledProviders: [Provider] {
        Provider.presets.filter { enabledProviderIDs.contains($0.id) }
    }

    var languagePair: LanguagePair {
        LanguagePair(
            primary: TranslationLanguage.language(for: primaryLanguageCode),
            secondary: TranslationLanguage.language(for: secondaryLanguageCode)
        )
    }

    /// Choosing the language already used by the other slot swaps the two, so the pair never
    /// contains the same language twice.
    func setPrimaryLanguageCode(_ code: String) {
        if code == secondaryLanguageCode {
            secondaryLanguageCode = primaryLanguageCode
        }
        primaryLanguageCode = code
    }

    func setSecondaryLanguageCode(_ code: String) {
        if code == primaryLanguageCode {
            primaryLanguageCode = secondaryLanguageCode
        }
        secondaryLanguageCode = code
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

    private static func defaultSecondaryLanguageCode(differentFrom primaryCode: String) -> String {
        let primaryLanguage = TranslationLanguage.language(for: primaryCode)
        if let systemCode = Locale.preferredLanguages.first.map(TranslationLanguage.baseLanguageCode(for:)),
           !primaryLanguage.matches(languageCode: systemCode) {
            return systemCode
        }
        return primaryLanguage.matches(languageCode: TranslationLanguage.english.code)
            ? TranslationLanguage.chinese.code
            : TranslationLanguage.english.code
    }
}
