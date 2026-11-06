//
// Created by ktiays on 2026/10/22.
// Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation
import XCTest
@testable import TextAnywhere

final class BigModelAdapterTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testTranslateSendsChatCompletionWithExplicitThinking() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            capturedBody = (try? JSONSerialization.jsonObject(with: StubURLProtocol.body(of: request))) as? [String: Any]
            return #"{"choices":[{"message":{"role":"assistant","content":"你好"}}]}"#
        }

        let provider = Provider.bigModel
        let translation = try await ProviderAdapterRegistry.adapter(for: provider.id, session: stubSession())
            .translate(
                TranslationRequest(text: "Hello", targetLanguage: TranslationLanguage.chinese),
                configuration: ProviderConfiguration(
                    providerID: provider.id,
                    baseURL: try XCTUnwrap(URL(string: provider.defaultBaseURL)),
                    modelID: "glm-4.7",
                    apiKey: "test-key",
                    thinkingEnabled: false
                )
            )

        XCTAssertEqual(translation, "你好")
        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        )
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(capturedBody?["model"] as? String, "glm-4.7")
        XCTAssertEqual((capturedBody?["thinking"] as? [String: Any])?["type"] as? String, "disabled")
    }

    func testFetchModelsReadsOpenAICompatibleList() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://open.bigmodel.cn/api/paas/v4/models")
            return #"{"object":"list","data":[{"id":"glm-4.7","object":"model"},{"id":"glm-4.5","object":"model"}]}"#
        }

        let provider = Provider.bigModel
        let models = try await ProviderAdapterRegistry.adapter(for: provider.id, session: stubSession())
            .fetchModels(
                configuration: ProviderConfiguration(
                    providerID: provider.id,
                    baseURL: try XCTUnwrap(URL(string: provider.defaultBaseURL)),
                    modelID: "",
                    apiKey: "test-key",
                    thinkingEnabled: false
                )
            )

        XCTAssertEqual(models.map(\.id), ["glm-4.5", "glm-4.7"])
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class StubURLProtocol: URLProtocol {

    nonisolated(unsafe) static var handler: ((URLRequest) -> String)?

    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let body = Data(handler(request).utf8)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
