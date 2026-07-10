//
//  Created by ktiays on 2026/4/15.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

struct Provider: Identifiable, Hashable, Equatable, Sendable {

    let id: ProviderIdentifier
    let name: String
    let iconAssetName: String?
    let systemImageName: String?

    init(id: ProviderIdentifier, name: String, iconAssetName: String? = nil, systemImageName: String? = nil) {
        self.id = id
        self.name = name
        self.iconAssetName = iconAssetName
        self.systemImageName = systemImageName
    }

    @ViewBuilder
    func iconView() -> some View {
        if let iconAssetName {
            Image(iconAssetName)
                .resizable()
                .aspectRatio(1.0, contentMode: .fit)
        } else if let systemImageName {
            Image(systemName: systemImageName)
                .resizable()
                .aspectRatio(1.0, contentMode: .fit)
        } else {
            Image(systemName: "cube")
                .resizable()
                .aspectRatio(1.0, contentMode: .fit)
        }
    }

    static let anthropic: Self = .init(id: .anthropic, name: "Anthropic", iconAssetName: "anthropic")

    static let openAI: Self = .init(id: .openAI, name: "OpenAI", iconAssetName: "openai")

    static let openRouter: Self = .init(id: .openRouter, name: "OpenRouter", iconAssetName: "openrouter")

    static let xAI: Self = .init(id: .xAI, name: "xAI", iconAssetName: "xai")

    static let bailian: Self = .init(id: .bailian, name: "Bailian", iconAssetName: "bailian")

    static let ollama: Self = .init(id: .ollama, name: "Ollama", iconAssetName: "ollama")

    static let presets: [Provider] = [
        .anthropic,
        .openAI,
        .openRouter,
        .xAI,
        .bailian,
        .ollama,
    ]

    static func provider(for identifier: ProviderIdentifier) -> Provider {
        presets.first { $0.id == identifier } ?? .bailian
    }

    var requiresAPIKey: Bool {
        id != .ollama
    }

    var defaultBaseURL: String {
        switch id {
        case .anthropic:
            "https://api.anthropic.com/v1"
        case .openAI:
            "https://api.openai.com/v1"
        case .openRouter:
            "https://openrouter.ai/api/v1"
        case .xAI:
            "https://api.x.ai/v1"
        case .bailian:
            "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .ollama:
            "http://localhost:11434"
        default:
            fatalError("Unspported provider: \(id)")
        }
    }

    var defaultModelID: String {
        id == .bailian ? "qwen-plus" : ""
    }
}

struct ProviderIdentifier: RawRepresentable, ExpressibleByStringLiteral, Hashable, Codable, Sendable {

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    static let anthropic: Self = "Anthropic"

    static let openAI: Self = "OpenAI"

    static let xAI: Self = "xAI"

    static let openRouter: Self = "OpenRouter"

    static let bailian: Self = "Bailian"

    static let ollama: Self = "Ollama"
}
