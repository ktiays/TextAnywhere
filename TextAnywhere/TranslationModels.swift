//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation

struct TranslationLanguage: Identifiable, Hashable, Codable, Sendable {

    let code: String
    let displayName: String

    var id: String { code }

    static let english = TranslationLanguage(code: "en", displayName: "English")
    static let chinese = TranslationLanguage(code: "zh", displayName: "Chinese")

    static let catalog: [TranslationLanguage] = {
        Locale.LanguageCode.isoLanguageCodes
            .filter { code in
                !["mul", "und", "zxx"].contains(code.identifier)
            }
            .compactMap { code in
                let identifier = code.identifier
                guard let displayName = Locale.current.localizedString(forLanguageCode: identifier) else {
                    return nil
                }
                return TranslationLanguage(code: identifier, displayName: displayName)
            }
            .uniqued(on: \TranslationLanguage.code)
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }()

    static func language(for code: String) -> TranslationLanguage {
        catalog.first { $0.code == code }
            ?? TranslationLanguage(
                code: code,
                displayName: Locale.current.localizedString(forLanguageCode: code) ?? code
            )
    }

    /// Reduces a BCP 47 identifier such as `zh-Hans` or `en-001` to its base language code,
    /// so recognizer output, system locales, and catalog entries can be compared.
    static func baseLanguageCode(for identifier: String) -> String {
        guard let languageCode = Locale.Language(identifier: identifier).languageCode else {
            return identifier
        }
        return languageCode.identifier(.alpha2) ?? languageCode.identifier
    }

    func matches(languageCode: String) -> Bool {
        Self.baseLanguageCode(for: code) == Self.baseLanguageCode(for: languageCode)
    }
}

enum TargetLanguageMode: String, CaseIterable, Identifiable, Sendable {

    case automatic
    case primary
    case secondary

    var id: String { rawValue }
}

struct LanguagePair: Equatable, Sendable {

    let primary: TranslationLanguage
    let secondary: TranslationLanguage

    /// In automatic mode, text in the primary language is translated into the secondary one,
    /// and everything else, including text whose language wasn't recognized, into the primary one.
    func targetLanguage(
        for mode: TargetLanguageMode,
        detectedLanguageCode: String?
    ) -> TranslationLanguage {
        switch mode {
        case .automatic:
            guard let detectedLanguageCode, primary.matches(languageCode: detectedLanguageCode) else {
                return primary
            }
            return secondary
        case .primary:
            return primary
        case .secondary:
            return secondary
        }
    }
}

struct ModelDescriptor: Identifiable, Hashable, Codable, Sendable {

    let id: String
    let displayName: String
}

struct ProviderConfiguration: Equatable, Sendable {

    let providerID: ProviderIdentifier
    let baseURL: URL
    let modelID: String
    let apiKey: String?
    let thinkingEnabled: Bool
}

struct TranslationRequest: Equatable, Sendable {

    let text: String
    let targetLanguage: TranslationLanguage
}

enum ProviderError: LocalizedError, Equatable {

    case invalidConfiguration(String)
    case invalidResponse
    case httpStatus(Int, String)
    case transport(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            message
        case .invalidResponse:
            "The provider returned an invalid response."
        case .httpStatus(let status, let message):
            message.isEmpty ? "The provider returned HTTP \(status)." : message
        case .transport(let message):
            message
        case .cancelled:
            "The translation was cancelled."
        }
    }
}

private extension Array {

    func uniqued<Key: Hashable>(on keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
