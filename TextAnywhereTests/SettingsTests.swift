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
        settings.targetLanguageCode = "ja"
        settings.setBaseURL("https://example.com/v1", for: .openRouter)
        settings.setModelID("example/model", for: .openRouter)
        settings.setThinkingEnabled(true, for: .openRouter)
        settings.setCachedModels(
            [ModelDescriptor(id: "example/model", displayName: "Example")],
            for: .openRouter
        )

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.selectedProviderID, .openRouter)
        XCTAssertEqual(restored.targetLanguageCode, "ja")
        XCTAssertEqual(restored.baseURL(for: .openRouter), "https://example.com/v1")
        XCTAssertEqual(restored.modelID(for: .openRouter), "example/model")
        XCTAssertTrue(restored.thinkingEnabled(for: .openRouter))
        XCTAssertFalse(restored.thinkingEnabled(for: .anthropic))
        XCTAssertEqual(restored.cachedModels(for: .openRouter).map(\.id), ["example/model"])
    }

    func testLanguageCatalogContainsUniqueEnglishEntry() {
        let englishEntries = TranslationLanguage.catalog.filter { $0.code == "en" }
        XCTAssertEqual(englishEntries.count, 1)
        XCTAssertFalse(englishEntries[0].displayName.isEmpty)
    }

    func testGlobalShortcutRoundTripsThroughCodable() throws {
        let shortcut = GlobalShortcut.defaultShortcut
        let data = try JSONEncoder().encode(shortcut)
        XCTAssertEqual(try JSONDecoder().decode(GlobalShortcut.self, from: data), shortcut)
    }
}
