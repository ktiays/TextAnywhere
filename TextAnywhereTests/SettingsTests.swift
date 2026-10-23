//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation
import XCTest
@testable import TextAnywhere

final class SettingsTests: XCTestCase {

    func testProviderPreferencesAndModelCachePersist() {
        let suiteName = "SettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        settings.selectedProviderID = .openRouter
        settings.setPrimaryLanguageCode("ja")
        settings.setSecondaryLanguageCode("fr")
        settings.targetLanguageMode = .secondary
        settings.setBaseURL("https://example.com/v1", for: .openRouter)
        settings.setModelID("example/model", for: .openRouter)
        settings.setThinkingEnabled(true, for: .openRouter)
        settings.isTrayEnabled = false
        settings.isTranslationButtonVisible = false
        settings.primaryButtonAction = .paste
        settings.setProviderEnabled(true, for: .openRouter)
        settings.setProviderEnabled(false, for: .bailian)
        settings.setCachedModels(
            [ModelDescriptor(id: "example/model", displayName: "Example")],
            for: .openRouter
        )

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.selectedProviderID, .openRouter)
        XCTAssertEqual(restored.primaryLanguageCode, "ja")
        XCTAssertEqual(restored.secondaryLanguageCode, "fr")
        XCTAssertEqual(restored.targetLanguageMode, .secondary)
        XCTAssertEqual(restored.baseURL(for: .openRouter), "https://example.com/v1")
        XCTAssertEqual(restored.modelID(for: .openRouter), "example/model")
        XCTAssertTrue(restored.thinkingEnabled(for: .openRouter))
        XCTAssertFalse(restored.thinkingEnabled(for: .anthropic))
        XCTAssertFalse(restored.isTrayEnabled)
        XCTAssertFalse(restored.isTranslationButtonVisible)
        XCTAssertEqual(restored.primaryButtonAction, .paste)
        XCTAssertTrue(restored.isProviderEnabled(.openRouter))
        XCTAssertFalse(restored.isProviderEnabled(.bailian))
        XCTAssertEqual(restored.cachedModels(for: .openRouter).map(\.id), ["example/model"])
    }

    func testLanguageCatalogContainsUniqueEnglishEntry() {
        let englishEntries = TranslationLanguage.catalog.filter { $0.code == "en" }
        XCTAssertEqual(englishEntries.count, 1)
        XCTAssertFalse(englishEntries[0].displayName.isEmpty)
    }

    func testProviderEnablementKeepsAnEnabledProviderSelected() {
        let suiteName = "SettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        settings.setProviderEnabled(true, for: .openAI)
        settings.setProviderEnabled(false, for: .bailian)
        XCTAssertEqual(settings.selectedProviderID, .openAI)

        settings.setProviderEnabled(false, for: .openAI)
        settings.setProviderEnabled(true, for: .anthropic)
        XCTAssertEqual(settings.selectedProviderID, .anthropic)
    }

    func testGlobalShortcutRoundTripsThroughCodable() throws {
        let shortcut = GlobalShortcut.defaultShortcut
        let data = try JSONEncoder().encode(shortcut)
        XCTAssertEqual(try JSONDecoder().decode(GlobalShortcut.self, from: data), shortcut)
    }

    func testTrayIsEnabledByDefault() {
        let suiteName = "SettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertTrue(AppSettings(defaults: defaults).isTrayEnabled)
    }

    func testEditorActionsUseTranslationDefaults() {
        let suiteName = "SettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.isTranslationButtonVisible)
        XCTAssertEqual(settings.primaryButtonAction, .translateAndPaste)
    }

    func testLanguagePairDefaultsToAutomaticWithDistinctLanguages() {
        let suiteName = "SettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.targetLanguageMode, .automatic)
        XCTAssertEqual(settings.primaryLanguageCode, "en")
        XCTAssertNotEqual(settings.primaryLanguageCode, settings.secondaryLanguageCode)
    }

    func testLegacyTargetLanguageBecomesPrimaryLanguage() {
        let suiteName = "SettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("de", forKey: "targetLanguage")

        XCTAssertEqual(AppSettings(defaults: defaults).primaryLanguageCode, "de")
    }

    func testChoosingTheOtherLanguageSwapsThePair() {
        let suiteName = "SettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        settings.setPrimaryLanguageCode("en")
        settings.setSecondaryLanguageCode("zh")

        settings.setPrimaryLanguageCode("zh")
        XCTAssertEqual(settings.primaryLanguageCode, "zh")
        XCTAssertEqual(settings.secondaryLanguageCode, "en")

        settings.setSecondaryLanguageCode("zh")
        XCTAssertEqual(settings.primaryLanguageCode, "en")
        XCTAssertEqual(settings.secondaryLanguageCode, "zh")
    }

    func testAutomaticTargetTranslatesBetweenThePair() {
        let pair = LanguagePair(
            primary: TranslationLanguage.language(for: "en"),
            secondary: TranslationLanguage.language(for: "zh")
        )

        XCTAssertEqual(pair.targetLanguage(for: .automatic, detectedLanguageCode: "en").code, "zh")
        XCTAssertEqual(pair.targetLanguage(for: .automatic, detectedLanguageCode: "zh").code, "en")
        XCTAssertEqual(pair.targetLanguage(for: .automatic, detectedLanguageCode: "ja").code, "en")
        XCTAssertEqual(pair.targetLanguage(for: .automatic, detectedLanguageCode: nil).code, "en")
        XCTAssertEqual(pair.targetLanguage(for: .primary, detectedLanguageCode: "en").code, "en")
        XCTAssertEqual(pair.targetLanguage(for: .secondary, detectedLanguageCode: "zh").code, "zh")
    }

    func testLanguageDetectorRecognizesCommonInputs() {
        XCTAssertEqual(LanguageDetector.languageCode(of: "Hello, how are you today?"), "en")
        XCTAssertEqual(LanguageDetector.languageCode(of: "你好，今天天气怎么样？"), "zh")
        XCTAssertEqual(LanguageDetector.languageCode(of: "我在用 Xcode 写 SwiftUI"), "zh")
        XCTAssertEqual(LanguageDetector.languageCode(of: "SwiftUI の View を作る"), "ja")
        XCTAssertNil(LanguageDetector.languageCode(of: ""))
        XCTAssertNil(LanguageDetector.languageCode(of: "123"))
    }

    func testOCRSettingsDefaultsAndPersistence() {
        let suiteName = "SettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.isOCREnabled)
        XCTAssertEqual(settings.ocrModel, .glmOCR)
        XCTAssertTrue(settings.isOCRScreenCaptureEnabled)
        XCTAssertTrue(settings.isOCRPasteAndDropEnabled)
        XCTAssertTrue(settings.isOCRFilePickerEnabled)
        XCTAssertFalse(settings.isOCRShortcutEnabled)
        XCTAssertEqual(settings.ocrShortcut, .defaultOCRShortcut)

        settings.isOCREnabled = false
        settings.isOCRScreenCaptureEnabled = false
        settings.isOCRPasteAndDropEnabled = false
        settings.isOCRFilePickerEnabled = false
        settings.isOCRShortcutEnabled = true
        settings.ocrShortcut = .defaultShortcut

        let restored = AppSettings(defaults: defaults)
        XCTAssertFalse(restored.isOCREnabled)
        XCTAssertFalse(restored.isOCRScreenCaptureEnabled)
        XCTAssertFalse(restored.isOCRPasteAndDropEnabled)
        XCTAssertFalse(restored.isOCRFilePickerEnabled)
        XCTAssertTrue(restored.isOCRShortcutEnabled)
        XCTAssertEqual(restored.ocrShortcut, .defaultShortcut)
    }

    func testSearchableMenuRanksExactAndPrefixMatchesFirst() {
        let english = SearchableMenuItem(id: "en", title: "English", searchTerms: ["en"])
        let bengali = SearchableMenuItem(id: "bn", title: "Bengali", searchTerms: ["bn"])
        XCTAssertEqual(english.matchRank(for: "EN"), 0)
        XCTAssertEqual(english.matchRank(for: "eng"), 1)
        XCTAssertEqual(bengali.matchRank(for: "en"), 2)
        XCTAssertNil(bengali.matchRank(for: "fr"))
    }
}
