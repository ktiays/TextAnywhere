//
//  Created by ktiays on 2026/11/6.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation

struct OCRClient {

    let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    func recognizeText(
        in document: OCRDocument,
        prompt: String,
        configuration: ProviderConfiguration
    ) async throws -> String {
        let provider = Provider.provider(for: configuration.providerID)
        let modelID = configuration.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else {
            throw ProviderError.invalidConfiguration("Choose an image-capable model in Settings → OCR.")
        }
        let apiKey = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !provider.requiresAPIKey || !apiKey.isEmpty else {
            throw ProviderError.invalidConfiguration("Set your \(provider.name) API key in Settings → Providers.")
        }
        guard let scheme = configuration.baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme), configuration.baseURL.host != nil else {
            throw ProviderError.invalidConfiguration("Enter a valid base URL in Settings → Providers → \(provider.name).")
        }
        try Task.checkCancellation()

        let path: String
        switch provider.id {
        case .openAI, .xAI: path = "responses"
        case .anthropic: path = "messages"
        case .ollama: path = "api/chat"
        default: path = "chat/completions"
        }
        var request = URLRequest(url: configuration.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if provider.id == .anthropic {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if provider.requiresAPIKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        switch provider.id {
        case .openAI, .xAI:
            request.httpBody = try encoder.encode(
                OCRResponsesRequest(
                    model: modelID,
                    instructions: prompt,
                    input: [OCRMessage(role: "user", content: .parts(
                        [.inputText("Recognize the text in these images.")]
                            + document.images.map { .inputImage($0.dataURI) }
                    ))],
                    store: false,
                    reasoning: configuration.thinkingEnabled ? OCRReasoning(effort: "low") : nil
                )
            )
        case .anthropic:
            request.httpBody = try encoder.encode(
                OCRAnthropicRequest(
                    model: modelID,
                    maxTokens: 8192,
                    system: prompt,
                    messages: [OCRMessage(role: "user", content: .parts(
                        document.images.map { .image($0) } + [.text("Recognize the text in these images.")]
                    ))],
                    thinking: configuration.thinkingEnabled ? OCRThinking(type: "adaptive") : nil
                )
            )
        case .ollama:
            request.httpBody = try encoder.encode(
                OCROllamaRequest(
                    model: modelID,
                    messages: [
                        OCRMessage(role: "system", content: .text(prompt)),
                        OCRMessage(
                            role: "user",
                            content: .text("Recognize the text in these images."),
                            images: document.images.map { $0.data.base64EncodedString() }
                        ),
                    ],
                    stream: false,
                    think: configuration.thinkingEnabled
                )
            )
        default:
            request.httpBody = try encoder.encode(
                OCRChatCompletionRequest(
                    model: modelID,
                    messages: [
                        OCRMessage(role: "system", content: .text(prompt)),
                        OCRMessage(role: "user", content: .parts(
                            [.text("Recognize the text in these images.")]
                                + document.images.map { .imageURL($0.dataURI) }
                        )),
                    ],
                    stream: false,
                    reasoning: provider.id == .openRouter
                        ? OCROpenRouterReasoning(enabled: configuration.thinkingEnabled) : nil,
                    enableThinking: provider.id == .bailian ? configuration.thinkingEnabled : nil,
                    thinking: provider.id == .bigModel || provider.id == .deepSeek
                        ? OCRThinking(type: configuration.thinkingEnabled ? "enabled" : "disabled") : nil
                )
            )
        }

        let data = try await ProviderHTTPClient(session: session).send(request)
        let text: String
        do {
            let decoder = JSONDecoder()
            switch provider.id {
            case .openAI, .xAI:
                text = try decoder.decode(OCRResponsesResponse.self, from: data).output
                    .filter { $0.type == "message" }
                    .flatMap { $0.content ?? [] }
                    .filter { $0.type == "output_text" }
                    .compactMap(\.text)
                    .joined()
            case .anthropic:
                text = try decoder.decode(OCRAnthropicResponse.self, from: data).content
                    .filter { $0.type == "text" }
                    .compactMap(\.text)
                    .joined()
            case .ollama:
                text = try decoder.decode(OCROllamaResponse.self, from: data).message.content
            default:
                let response = try decoder.decode(OCRChatCompletionResponse.self, from: data)
                guard let content = response.choices.first?.message.content else {
                    throw ProviderError.invalidResponse
                }
                text = content
            }
        } catch {
            throw ProviderError.invalidResponse
        }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            throw ProviderError.invalidConfiguration("No text was recognized.")
        }
        return result
    }
}

private struct OCRMessage: Encodable {
    let role: String
    let content: OCRMessageContent
    var images: [String]? = nil
}

private enum OCRMessageContent: Encodable {
    case text(String)
    case parts([OCRContentPart])

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .parts(let parts): try container.encode(parts)
        }
    }
}

private enum OCRContentPart: Encodable {
    case text(String)
    case inputText(String)
    case inputImage(String)
    case imageURL(String)
    case image(OCRImage)

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text), .inputText(let text):
            try container.encode(text, forKey: .text)
            try container.encode(type, forKey: .type)
        case .inputImage(let url):
            try container.encode(type, forKey: .type)
            try container.encode(url, forKey: .imageURL)
            try container.encode("high", forKey: .detail)
        case .imageURL(let url):
            try container.encode(type, forKey: .type)
            try container.encode(ImageURL(url: url), forKey: .imageURL)
        case .image(let image):
            try container.encode(type, forKey: .type)
            try container.encode(
                ImageSource(type: "base64", mediaType: image.mimeType, data: image.data.base64EncodedString()),
                forKey: .source
            )
        }
    }

    private var type: String {
        switch self {
        case .text: "text"
        case .inputText: "input_text"
        case .inputImage: "input_image"
        case .imageURL: "image_url"
        case .image: "image"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, detail, source
        case imageURL = "image_url"
    }

    private struct ImageURL: Encodable {
        let url: String
    }

    private struct ImageSource: Encodable {
        let type: String
        let mediaType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case type, data
            case mediaType = "media_type"
        }
    }
}

private struct OCRResponsesRequest: Encodable {
    let model: String
    let instructions: String
    let input: [OCRMessage]
    let store: Bool
    let reasoning: OCRReasoning?
}

private struct OCRChatCompletionRequest: Encodable {
    let model: String
    let messages: [OCRMessage]
    let stream: Bool
    let reasoning: OCROpenRouterReasoning?
    let enableThinking: Bool?
    let thinking: OCRThinking?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, reasoning, thinking
        case enableThinking = "enable_thinking"
    }
}

private struct OCRAnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [OCRMessage]
    let thinking: OCRThinking?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, thinking
        case maxTokens = "max_tokens"
    }
}

private struct OCROllamaRequest: Encodable {
    let model: String
    let messages: [OCRMessage]
    let stream: Bool
    let think: Bool
}

private struct OCRReasoning: Encodable {
    let effort: String
}

private struct OCROpenRouterReasoning: Encodable {
    let enabled: Bool
}

private struct OCRThinking: Encodable {
    let type: String
}

private struct OCRResultMessage: Decodable {
    let content: String
}

private struct OCRChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: OCRResultMessage
    }
}

private struct OCROllamaResponse: Decodable {
    let message: OCRResultMessage
}

private struct OCRResponsesResponse: Decodable {
    let output: [Output]

    struct Output: Decodable {
        let type: String
        let content: [OCRResultBlock]?
    }
}

private struct OCRAnthropicResponse: Decodable {
    let content: [OCRResultBlock]
}

private struct OCRResultBlock: Decodable {
    let type: String
    let text: String?
}
