//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation
import XCTest
@testable import TextAnywhere

final class ProviderAdaptersTests: XCTestCase {

    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testModelDiscoveryForEveryProvider() async throws {
        let cases: [(ProviderIdentifier, String, String, [String])] = [
            (.anthropic, "/v1/models", #"{"data":[{"id":"claude-test","display_name":"Claude Test"}]}"#, ["claude-test"]),
            (.openAI, "/v1/models", #"{"data":[{"id":"gpt-test"}]}"#, ["gpt-test"]),
            (.openRouter, "/api/v1/models", #"{"data":[{"id":"openai/gpt-test","name":"GPT Test"}]}"#, ["openai/gpt-test"]),
            (.xAI, "/v1/language-models", #"{"models":[{"id":"grok-test"}]}"#, ["grok-test"]),
            (.bailian, "/compatible-mode/v1/models", #"{"data":[{"id":"qwen-test"},{"id":"embedding-test"}]}"#, ["qwen-test"]),
            (.deepSeek, "/models", #"{"data":[{"id":"deepseek-chat"}]}"#, ["deepseek-chat"]),
            (.ollama, "/api/tags", #"{"models":[{"name":"qwen:latest","model":"qwen:latest"}]}"#, ["qwen:latest"]),
        ]

        for testCase in cases {
            URLProtocolStub.handler = { request in
                XCTAssertEqual(request.url?.path, testCase.1)
                return try Self.response(for: request, body: testCase.2)
            }

            let adapter = ProviderAdapterRegistry.adapter(
                for: testCase.0,
                session: stubbedSession()
            )
            let models = try await adapter.fetchModels(configuration: configuration(for: testCase.0))
            XCTAssertEqual(models.map(\.id), testCase.3)
        }
    }

    func testTranslationForEveryProvider() async throws {
        let cases: [(ProviderIdentifier, String, String)] = [
            (.anthropic, "/v1/messages", #"{"content":[{"type":"text","text":"Bonjour"}]}"#),
            (.openAI, "/v1/responses", Self.responsesBody),
            (.openRouter, "/api/v1/chat/completions", Self.chatBody),
            (.xAI, "/v1/responses", Self.responsesBody),
            (.bailian, "/compatible-mode/v1/chat/completions", Self.chatBody),
            (.deepSeek, "/chat/completions", Self.chatBody),
            (.ollama, "/api/chat", #"{"message":{"role":"assistant","content":"Bonjour"}}"#),
        ]

        for testCase in cases {
            URLProtocolStub.handler = { request in
                XCTAssertEqual(request.url?.path, testCase.1)
                XCTAssertEqual(request.httpMethod, "POST")
                let body = try request.bodyData()
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(object["model"] as? String, "test-model")
                let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))
                XCTAssertTrue(
                    bodyText.contains("Text: Hello"),
                    "The source text must be wrapped in the plain-text template"
                )
                if testCase.0 == .openAI || testCase.0 == .xAI {
                    XCTAssertEqual(object["store"] as? Bool, false)
                }
                return try Self.response(for: request, body: testCase.2)
            }

            let adapter = ProviderAdapterRegistry.adapter(
                for: testCase.0,
                session: stubbedSession()
            )
            let result = try await adapter.translate(
                TranslationRequest(text: "Hello", targetLanguage: .init(code: "fr", displayName: "French")),
                configuration: configuration(for: testCase.0)
            )
            XCTAssertEqual(result, "Bonjour")
        }
    }

    func testThinkingParametersForEveryProvider() async throws {
        let cases: [(ProviderIdentifier, String, ([String: Any]) -> Any?)] = [
            (.anthropic, #"{"content":[{"type":"text","text":"Bonjour"}]}"#, { ($0["thinking"] as? [String: Any])?["type"] }),
            (.openAI, Self.responsesBody, { ($0["reasoning"] as? [String: Any])?["effort"] }),
            (.openRouter, Self.chatBody, { ($0["reasoning"] as? [String: Any])?["enabled"] }),
            (.xAI, Self.responsesBody, { ($0["reasoning"] as? [String: Any])?["effort"] }),
            (.bailian, Self.chatBody, { $0["enable_thinking"] }),
            (.deepSeek, Self.chatBody, { ($0["thinking"] as? [String: Any])?["type"] }),
            (.ollama, #"{"message":{"role":"assistant","content":"Bonjour"}}"#, { $0["think"] }),
        ]

        for testCase in cases {
            let adapter = ProviderAdapterRegistry.adapter(
                for: testCase.0,
                session: stubbedSession()
            )

            for thinkingEnabled in [true, false] {
                let capture = BodyCapture()
                URLProtocolStub.handler = { request in
                    capture.body = try JSONSerialization.jsonObject(with: request.bodyData()) as? [String: Any]
                    return try Self.response(for: request, body: testCase.1)
                }

                _ = try await adapter.translate(
                    TranslationRequest(text: "Hello", targetLanguage: .english),
                    configuration: configuration(for: testCase.0, thinkingEnabled: thinkingEnabled)
                )

                let body = try XCTUnwrap(capture.body)
                if thinkingEnabled {
                    XCTAssertNotNil(
                        testCase.2(body),
                        "Expected a thinking parameter for \(testCase.0.rawValue)"
                    )
                } else if testCase.0 == .bailian {
                    XCTAssertEqual(body["enable_thinking"] as? Bool, false)
                } else if testCase.0 == .deepSeek {
                    XCTAssertEqual(
                        (body["thinking"] as? [String: Any])?["type"] as? String,
                        "disabled"
                    )
                } else {
                    XCTAssertNil(
                        testCase.2(body),
                        "Expected no thinking parameter for \(testCase.0.rawValue)"
                    )
                }
            }
        }
    }

    func testHTTPErrorIncludesProviderMessage() async {
        URLProtocolStub.handler = { request in
            try Self.response(
                for: request,
                statusCode: 429,
                body: #"{"error":{"message":"Rate limited"}}"#
            )
        }

        let adapter = ProviderAdapterRegistry.adapter(for: .openAI, session: stubbedSession())
        do {
            _ = try await adapter.fetchModels(configuration: configuration(for: .openAI))
            XCTFail("Expected the request to fail")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .httpStatus(429, "Rate limited"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAuthenticationFailureIsMapped() async {
        URLProtocolStub.handler = { request in
            try Self.response(
                for: request,
                statusCode: 401,
                body: #"{"error":{"message":"Invalid API key"}}"#
            )
        }

        let adapter = ProviderAdapterRegistry.adapter(for: .anthropic, session: stubbedSession())
        do {
            _ = try await adapter.fetchModels(configuration: configuration(for: .anthropic))
            XCTFail("Expected the request to fail")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .httpStatus(401, "Invalid API key"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEmptyTranslationOutputIsRejected() async {
        URLProtocolStub.handler = { request in
            try Self.response(
                for: request,
                body: #"{"output":[{"type":"message","content":[{"type":"output_text","text":"  "}]}]}"#
            )
        }

        let adapter = ProviderAdapterRegistry.adapter(for: .openAI, session: stubbedSession())
        do {
            _ = try await adapter.translate(
                TranslationRequest(text: "Hello", targetLanguage: .english),
                configuration: configuration(for: .openAI)
            )
            XCTFail("Expected the response to be rejected")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellationIsMapped() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedURLProtocol.self]
        let adapter = ProviderAdapterRegistry.adapter(
            for: .openAI,
            session: URLSession(configuration: configuration)
        )

        let task = Task {
            try await adapter.fetchModels(configuration: self.configuration(for: .openAI))
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected the request to be cancelled")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedResponseIsRejected() async {
        URLProtocolStub.handler = { request in
            try Self.response(for: request, body: "not-json")
        }

        let adapter = ProviderAdapterRegistry.adapter(for: .ollama, session: stubbedSession())
        do {
            _ = try await adapter.fetchModels(configuration: configuration(for: .ollama))
            XCTFail("Expected the response to be rejected")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func configuration(
        for providerID: ProviderIdentifier,
        thinkingEnabled: Bool = false
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            providerID: providerID,
            baseURL: Provider.provider(for: providerID).defaultBaseURLURL,
            modelID: "test-model",
            apiKey: providerID == .ollama ? nil : "test-key",
            thinkingEnabled: thinkingEnabled
        )
    }

    private func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) throws -> (HTTPURLResponse, Data) {
        guard let url = request.url,
              let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
              ) else {
            throw URLError(.badServerResponse)
        }
        return (response, Data(body.utf8))
    }

    private static let responsesBody = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Bonjour"}]}]}"#
    private static let chatBody = #"{"choices":[{"message":{"role":"assistant","content":"Bonjour"}}]}"#
}

private final class BodyCapture: @unchecked Sendable {
    var body: [String: Any]?
}

private final class URLProtocolStub: URLProtocol {

    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override nonisolated class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override nonisolated class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override nonisolated func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override nonisolated func stopLoading() {}
}

private final class DelayedURLProtocol: URLProtocol {

    override nonisolated class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override nonisolated class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override nonisolated func startLoading() {
        Thread.sleep(forTimeInterval: 1)
        guard let url = request.url else { return }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        guard let response else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"data":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override nonisolated func stopLoading() {}
}

private extension Provider {

    var defaultBaseURLURL: URL {
        URL(string: defaultBaseURL) ?? URL(fileURLWithPath: "/")
    }
}

private extension URLRequest {

    func bodyData() throws -> Data {
        if let httpBody {
            return httpBody
        }
        guard let httpBodyStream else {
            throw URLError(.cannotDecodeContentData)
        }

        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while httpBodyStream.hasBytesAvailable {
            let count = httpBodyStream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw httpBodyStream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
