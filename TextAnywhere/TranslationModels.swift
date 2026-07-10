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

    static var catalog: [TranslationLanguage] {
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
    }

    static func language(for code: String) -> TranslationLanguage {
        catalog.first { $0.code == code }
            ?? TranslationLanguage(
                code: code,
                displayName: Locale.current.localizedString(forLanguageCode: code) ?? code
            )
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
