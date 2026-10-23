//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation

protocol TranslationProviderAdapter {

    func fetchModels(configuration: ProviderConfiguration) async throws -> [ModelDescriptor]
    func translate(_ request: TranslationRequest, configuration: ProviderConfiguration) async throws -> String
}

enum ProviderAdapterRegistry {

    static func adapter(
        for providerID: ProviderIdentifier,
        session: URLSession = .shared
    ) -> any TranslationProviderAdapter {
        if providerID == .anthropic { return AnthropicAdapter(session: session) }
        if providerID == .openAI { return OpenAIAdapter(session: session) }
        if providerID == .openRouter { return OpenRouterAdapter(session: session) }
        if providerID == .xAI { return XAIAdapter(session: session) }
        if providerID == .bailian { return BailianAdapter(session: session) }
        if providerID == .deepSeek { return DeepSeekAdapter(session: session) }
        if providerID == .bigModel { return BigModelAdapter(session: session) }
        return OllamaAdapter(session: session)
    }
}

struct ProviderHTTPClient {

    let session: URLSession

    func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ProviderError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ProviderError.httpStatus(
                    httpResponse.statusCode,
                    Self.errorMessage(from: data)
                )
            }
            return data
        } catch is CancellationError {
            throw ProviderError.cancelled
        } catch let error as ProviderError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw ProviderError.cancelled
        } catch {
            throw ProviderError.transport(error.localizedDescription)
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return String(data: data, encoding: .utf8) ?? ""
        }

        if let dictionary = object as? [String: Any] {
            if let error = dictionary["error"] as? String {
                return error
            }
            if let error = dictionary["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = dictionary["message"] as? String {
                return message
            }
        }
        return ""
    }
}

private struct OpenAIAdapter: TranslationProviderAdapter {

    let session: URLSession

    func fetchModels(configuration: ProviderConfiguration) async throws -> [ModelDescriptor] {
        let request = try authorizedRequest(
            url: endpoint(configuration.baseURL, path: "models"),
            apiKey: requiredAPIKey(configuration)
        )
        let data = try await ProviderHTTPClient(session: session).send(request)
        let response = try decode(ModelListResponse.self, from: data)
        return normalizedModels(response.data.map { ModelDescriptor(id: $0.id, displayName: $0.id) })
    }

    func translate(_ request: TranslationRequest, configuration: ProviderConfiguration) async throws -> String {
        var urlRequest = try authorizedRequest(
            url: endpoint(configuration.baseURL, path: "responses"),
            apiKey: requiredAPIKey(configuration)
        )
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(
            ResponsesRequest(
                model: requiredModelID(configuration),
                instructions: TranslationPrompt.systemInstruction(for: request.targetLanguage),
                input: TranslationPrompt.userMessage(for: request.text),
                store: false,
                reasoning: configuration.thinkingEnabled ? ResponsesReasoning(effort: "low") : nil
            )
        )

        let data = try await ProviderHTTPClient(session: session).send(urlRequest)
        return try outputText(from: decode(ResponsesResponse.self, from: data))
    }
}

private struct XAIAdapter: TranslationProviderAdapter {

    let session: URLSession

    func fetchModels(configuration: ProviderConfiguration) async throws -> [ModelDescriptor] {
        let request = try authorizedRequest(
            url: endpoint(configuration.baseURL, path: "language-models"),
            apiKey: requiredAPIKey(configuration)
        )
        let data = try await ProviderHTTPClient(session: session).send(request)
        let response = try decode(XAIModelListResponse.self, from: data)
        return normalizedModels(response.models.map { ModelDescriptor(id: $0.id, displayName: $0.id) })
    }

    func translate(_ request: TranslationRequest, configuration: ProviderConfiguration) async throws -> String {
        var urlRequest = try authorizedRequest(
            url: endpoint(configuration.baseURL, path: "responses"),
            apiKey: requiredAPIKey(configuration)
        )
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(
            ResponsesRequest(
                model: requiredModelID(configuration),
                instructions: TranslationPrompt.systemInstruction(for: request.targetLanguage),
                input: TranslationPrompt.userMessage(for: request.text),
                store: false,
                reasoning: configuration.thinkingEnabled ? ResponsesReasoning(effort: "low") : nil
            )
        )

        let data = try await ProviderHTTPClient(session: session).send(urlRequest)
        return try outputText(from: decode(ResponsesResponse.self, from: data))
    }
}

private struct AnthropicAdapter: TranslationProviderAdapter {

    let session: URLSession

    func fetchModels(configuration: ProviderConfiguration) async throws -> [ModelDescriptor] {
        var components = URLComponents(
            url: endpoint(configuration.baseURL, path: "models"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "limit", value: "1000")]
        guard let url = components?.url else {
            throw ProviderError.invalidConfiguration("The Anthropic base URL is invalid.")
        }

        var request = URLRequest(url: url)
        request.setValue(try requiredAPIKey(configuration), forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let data = try await ProviderHTTPClient(session: session).send(request)
        let response = try decode(AnthropicModelListResponse.self, from: data)
        return normalizedModels(
            response.data.map { ModelDescriptor(id: $0.id, displayName: $0.displayName) }
        )
    }

    func translate(_ request: TranslationRequest, configuration: ProviderConfiguration) async throws -> String {
        var urlRequest = URLRequest(url: endpoint(configuration.baseURL, path: "messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(try requiredAPIKey(configuration), forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(
            AnthropicMessageRequest(
                model: requiredModelID(configuration),
                maxTokens: 8192,
                system: TranslationPrompt.systemInstruction(for: request.targetLanguage),
                messages: [ChatMessage(role: "user", content: TranslationPrompt.userMessage(for: request.text))],
                thinking: configuration.thinkingEnabled ? AnthropicThinkingConfiguration(type: "adaptive") : nil
            )
        )

        let data = try await ProviderHTTPClient(session: session).send(urlRequest)
        let response = try decode(AnthropicMessageResponse.self, from: data)
        let text = response.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
        return try validatedOutput(text)
    }
}

private struct OpenRouterAdapter: TranslationProviderAdapter {

    let session: URLSession

    func fetchModels(configuration: ProviderConfiguration) async throws -> [ModelDescriptor] {
        var components = URLComponents(
            url: endpoint(configuration.baseURL, path: "models"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "output_modalities", value: "text")]
        guard let url = components?.url else {
            throw ProviderError.invalidConfiguration("The OpenRouter base URL is invalid.")
        }
        let request = try authorizedRequest(url: url, apiKey: requiredAPIKey(configuration))
        let data = try await ProviderHTTPClient(session: session).send(request)
        let response = try decode(OpenRouterModelListResponse.self, from: data)
        return normalizedModels(
            response.data.map { ModelDescriptor(id: $0.id, displayName: $0.name) }
        )
    }

    func translate(_ request: TranslationRequest, configuration: ProviderConfiguration) async throws -> String {
        try await translateChatCompletion(
            request,
            configuration: configuration,
            session: session,
            apiKey: requiredAPIKey(configuration),
            reasoning: configuration.thinkingEnabled ? OpenRouterReasoning(enabled: true) : nil
        )
    }
}

private struct BailianAdapter: TranslationProviderAdapter {

    let session: URLSession

    func fetchModels(configuration: ProviderConfiguration) async throws -> [ModelDescriptor] {
        let request = try authorizedRequest(
            url: endpoint(configuration.baseURL, path: "models"),
            apiKey: requiredAPIKey(configuration)
        )
        let data = try await ProviderHTTPClient(session: session).send(request)
        let response = try decode(ModelListResponse.self, from: data)
        return normalizedModels(
            response.data
                .filter { $0.id.localizedCaseInsensitiveContains("qwen") }
                .map { ModelDescriptor(id: $0.id, displayName: $0.id) }
        )
    }

    func translate(_ request: TranslationRequest, configuration: ProviderConfiguration) async throws -> String {
        // Qwen-MT rejects system/assistant roles and requires translation_options.
        if isQwenMtModel(configuration.modelID) {
            return try await translateQwenMt(
                request,
                configuration: configuration,
                session: session,
                apiKey: requiredAPIKey(configuration)
            )
        }

        // DashScope requires an explicit `enable_thinking` value on non-streaming calls
        // to reasoning-capable models, so the flag is always sent for this provider.
        return try await translateChatCompletion(
            request,
            configuration: configuration,
            session: session,
            apiKey: requiredAPIKey(configuration),
            enableThinking: configuration.thinkingEnabled
        )
    }
}

private struct DeepSeekAdapter: TranslationProviderAdapter {

    let session: URLSession

    func fetchModels(configuration: ProviderConfiguration) async throws -> [ModelDescriptor] {
        let request = try authorizedRequest(
            url: endpoint(configuration.baseURL, path: "models"),
            apiKey: requiredAPIKey(configuration)
        )
        let data = try await ProviderHTTPClient(session: session).send(request)
        let response = try decode(ModelListResponse.self, from: data)
        return normalizedModels(response.data.map { ModelDescriptor(id: $0.id, displayName: $0.id) })
    }

    func translate(_ request: TranslationRequest, configuration: ProviderConfiguration) async throws -> String {
        // DeepSeek v4 models default to thinking mode. The parameter must be
        // set explicitly; omitting it keeps thinking enabled.
        try await translateChatCompletion(
            request,
            configuration: configuration,
            session: session,
            apiKey: requiredAPIKey(configuration),
            thinking: ThinkingTypeConfiguration(
                type: configuration.thinkingEnabled ? "enabled" : "disabled"
            )
        )
    }
}

private struct BigModelAdapter: TranslationProviderAdapter {

    let session: URLSession

    func fetchModels(configuration: ProviderConfiguration) async throws -> [ModelDescriptor] {
        let request = try authorizedRequest(
            url: endpoint(configuration.baseURL, path: "models"),
            apiKey: requiredAPIKey(configuration)
        )
        let data = try await ProviderHTTPClient(session: session).send(request)
        let response = try decode(ModelListResponse.self, from: data)
        return normalizedModels(response.data.map { ModelDescriptor(id: $0.id, displayName: $0.id) })
    }

    func translate(_ request: TranslationRequest, configuration: ProviderConfiguration) async throws -> String {
        // GLM-4.7 and later models think by default, so `thinking` is always sent explicitly.
        try await translateChatCompletion(
            request,
            configuration: configuration,
            session: session,
            apiKey: requiredAPIKey(configuration),
            thinking: ThinkingTypeConfiguration(
                type: configuration.thinkingEnabled ? "enabled" : "disabled"
            )
        )
    }
}

private struct OllamaAdapter: TranslationProviderAdapter {

    let session: URLSession

    func fetchModels(configuration: ProviderConfiguration) async throws -> [ModelDescriptor] {
        let request = URLRequest(url: endpoint(configuration.baseURL, path: "api/tags"))
        let data = try await ProviderHTTPClient(session: session).send(request)
        let response = try decode(OllamaModelListResponse.self, from: data)
        return normalizedModels(
            response.models.map {
                let identifier = $0.model ?? $0.name
                return ModelDescriptor(id: identifier, displayName: identifier)
            }
        )
    }

    func translate(_ request: TranslationRequest, configuration: ProviderConfiguration) async throws -> String {
        var urlRequest = URLRequest(url: endpoint(configuration.baseURL, path: "api/chat"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(
            OllamaChatRequest(
                model: requiredModelID(configuration),
                messages: [
                    ChatMessage(
                        role: "system",
                        content: TranslationPrompt.systemInstruction(for: request.targetLanguage)
                    ),
                    ChatMessage(role: "user", content: TranslationPrompt.userMessage(for: request.text)),
                ],
                stream: false,
                think: configuration.thinkingEnabled ? true : nil
            )
        )

        let data = try await ProviderHTTPClient(session: session).send(urlRequest)
        let response = try decode(OllamaChatResponse.self, from: data)
        return try validatedOutput(response.message.content)
    }
}

private func translateQwenMt(
    _ request: TranslationRequest,
    configuration: ProviderConfiguration,
    session: URLSession,
    apiKey: String
) async throws -> String {
    var urlRequest = try authorizedRequest(
        url: endpoint(configuration.baseURL, path: "chat/completions"),
        apiKey: apiKey
    )
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONEncoder().encode(
        QwenMtChatCompletionRequest(
            model: requiredModelID(configuration),
            messages: [ChatMessage(role: "user", content: request.text)],
            stream: false,
            translationOptions: QwenMtTranslationOptions(
                sourceLang: "auto",
                targetLang: qwenMtLanguageName(for: request.targetLanguage)
            )
        )
    )

    let data = try await ProviderHTTPClient(session: session).send(urlRequest)
    let response = try decode(ChatCompletionResponse.self, from: data)
    guard let content = response.choices.first?.message.content else {
        throw ProviderError.invalidResponse
    }
    return try validatedOutput(content)
}

private func translateChatCompletion(
    _ request: TranslationRequest,
    configuration: ProviderConfiguration,
    session: URLSession,
    apiKey: String,
    reasoning: OpenRouterReasoning? = nil,
    enableThinking: Bool? = nil,
    thinking: ThinkingTypeConfiguration? = nil
) async throws -> String {
    var urlRequest = try authorizedRequest(
        url: endpoint(configuration.baseURL, path: "chat/completions"),
        apiKey: apiKey
    )
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONEncoder().encode(
        ChatCompletionRequest(
            model: requiredModelID(configuration),
            messages: [
                ChatMessage(
                    role: "system",
                    content: TranslationPrompt.systemInstruction(for: request.targetLanguage)
                ),
                ChatMessage(role: "user", content: TranslationPrompt.userMessage(for: request.text)),
            ],
            stream: false,
            reasoning: reasoning,
            enableThinking: enableThinking,
            thinking: thinking
        )
    )

    let data = try await ProviderHTTPClient(session: session).send(urlRequest)
    let response = try decode(ChatCompletionResponse.self, from: data)
    guard let content = response.choices.first?.message.content else {
        throw ProviderError.invalidResponse
    }
    return try validatedOutput(content)
}

private func isQwenMtModel(_ modelID: String) -> Bool {
    modelID
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .hasPrefix("qwen-mt-")
}

private func qwenMtLanguageName(for language: TranslationLanguage) -> String {
    let code = language.code.trimmingCharacters(in: .whitespacesAndNewlines)
    if let mapped = qwenMtLanguageNames[code] {
        return mapped
    }

    let normalized = code.lowercased().replacingOccurrences(of: "_", with: "-")
    if normalized.hasPrefix("zh-hant") || normalized.hasPrefix("zh-tw") || normalized.hasPrefix("zh-hk") {
        return "Traditional Chinese"
    }
    if normalized == "zh" || normalized.hasPrefix("zh-") {
        return "Chinese"
    }

    return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
}

private let qwenMtLanguageNames: [String: String] = [
    "auto": "auto",
    "en": "English",
    "zh": "Chinese",
    "zh-CN": "Chinese",
    "zh-Hans": "Chinese",
    "zh-TW": "Traditional Chinese",
    "zh-HK": "Traditional Chinese",
    "zh-Hant": "Traditional Chinese",
    "ja": "Japanese",
    "ko": "Korean",
    "fr": "French",
    "de": "German",
    "es": "Spanish",
    "pt": "Portuguese",
    "ru": "Russian",
    "ar": "Arabic",
    "it": "Italian",
    "nl": "Dutch",
    "th": "Thai",
    "vi": "Vietnamese",
]

private func requiredAPIKey(_ configuration: ProviderConfiguration) throws -> String {
    guard let apiKey = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
          !apiKey.isEmpty else {
        throw ProviderError.invalidConfiguration("Enter an API key for the selected provider.")
    }
    return apiKey
}

private func requiredModelID(_ configuration: ProviderConfiguration) throws -> String {
    let modelID = configuration.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !modelID.isEmpty else {
        throw ProviderError.invalidConfiguration("Select or enter a model.")
    }
    return modelID
}

private func endpoint(_ baseURL: URL, path: String) -> URL {
    path.split(separator: "/").reduce(baseURL) { partialURL, component in
        partialURL.appendingPathComponent(String(component))
    }
}

private func authorizedRequest(url: URL, apiKey: String) throws -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    return request
}

private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw ProviderError.invalidResponse
    }
}

private func outputText(from response: ResponsesResponse) throws -> String {
    let text = response.output
        .filter { $0.type == "message" }
        .flatMap(\.content)
        .filter { $0.type == "output_text" }
        .compactMap(\.text)
        .joined()
    return try validatedOutput(text)
}

private func validatedOutput(_ text: String) throws -> String {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ProviderError.invalidResponse
    }
    return text
}

private func normalizedModels(_ models: [ModelDescriptor]) -> [ModelDescriptor] {
    var seen = Set<String>()
    return models
        .filter { seen.insert($0.id).inserted }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
}

private struct ModelListResponse: Decodable {
    let data: [ModelItem]
}

private struct ModelItem: Decodable {
    let id: String
}

private struct XAIModelListResponse: Decodable {
    let models: [ModelItem]
}

private struct AnthropicModelListResponse: Decodable {
    let data: [AnthropicModelItem]
}

private struct AnthropicModelItem: Decodable {
    let id: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

private struct OpenRouterModelListResponse: Decodable {
    let data: [OpenRouterModelItem]
}

private struct OpenRouterModelItem: Decodable {
    let id: String
    let name: String
}

private struct OllamaModelListResponse: Decodable {
    let models: [OllamaModelItem]
}

private struct OllamaModelItem: Decodable {
    let name: String
    let model: String?
}

private struct ResponsesRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let store: Bool
    let reasoning: ResponsesReasoning?
}

private struct ResponsesReasoning: Encodable {
    let effort: String
}

private struct OpenRouterReasoning: Encodable {
    let enabled: Bool
}

private struct ThinkingTypeConfiguration: Encodable {
    let type: String
}

private struct AnthropicThinkingConfiguration: Encodable {
    let type: String
}

private struct ResponsesResponse: Decodable {
    let output: [ResponsesOutputItem]
}

private struct ResponsesOutputItem: Decodable {
    let type: String
    let content: [ResponsesContentItem]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        content = try container.decodeIfPresent([ResponsesContentItem].self, forKey: .content) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case content
    }
}

private struct ResponsesContentItem: Decodable {
    let type: String
    let text: String?
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct QwenMtTranslationOptions: Encodable {
    let sourceLang: String
    let targetLang: String

    enum CodingKeys: String, CodingKey {
        case sourceLang = "source_lang"
        case targetLang = "target_lang"
    }
}

private struct QwenMtChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let translationOptions: QwenMtTranslationOptions

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case translationOptions = "translation_options"
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let reasoning: OpenRouterReasoning?
    let enableThinking: Bool?
    let thinking: ThinkingTypeConfiguration?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case reasoning
        case enableThinking = "enable_thinking"
        case thinking
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [ChatCompletionChoice]
}

private struct ChatCompletionChoice: Decodable {
    let message: ChatMessage
}

private struct AnthropicMessageRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ChatMessage]
    let thinking: AnthropicThinkingConfiguration?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case thinking
    }
}

private struct AnthropicMessageResponse: Decodable {
    let content: [AnthropicContentBlock]
}

private struct AnthropicContentBlock: Decodable {
    let type: String
    let text: String?
}

private struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let think: Bool?
}

private struct OllamaChatResponse: Decodable {
    let message: ChatMessage
}
