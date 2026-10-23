//
// Created by ktiays on 2026/10/22.
// Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import Foundation
import UniformTypeIdentifiers
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

    func testOCRSendsLayoutParsingRequestAndReadsMarkdown() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        StubURLProtocol.handler = { request in
            capturedRequest = request
            capturedBody = (try? JSONSerialization.jsonObject(with: StubURLProtocol.body(of: request))) as? [String: Any]
            return #"{"id":"task_1","created":1727156815,"model":"GLM-OCR","md_results":"  # Title\nBody  "}"#
        }

        let document = try OCRDocument(source: .imageData(Self.pngData()))
        let text = try await OCRClient(session: stubSession()).recognizeText(
            in: document,
            configuration: OCRConfiguration(
                baseURL: Provider.bigModel.defaultBaseURL,
                model: .glmOCR,
                apiKey: "test-key"
            )
        )

        XCTAssertEqual(text, "# Title\nBody")
        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://open.bigmodel.cn/api/paas/v4/layout_parsing"
        )
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(capturedBody?["model"] as? String, "glm-ocr")
        XCTAssertEqual(
            capturedBody?["file"] as? String,
            "data:image/png;base64,\(Self.pngData().base64EncodedString())"
        )
    }

    func testOCRRequiresAPIKey() {
        XCTAssertThrowsError(
            try OCRConfiguration(baseURL: Provider.bigModel.defaultBaseURL, model: .glmOCR, apiKey: " ")
        )
    }

    func testOCRDocumentConvertsUnsupportedImageFormatsToPNG() throws {
        let image = try XCTUnwrap(NSImage(data: Self.pngData()))
        let tiff = try XCTUnwrap(image.tiffRepresentation)

        let document = try OCRDocument(source: .imageData(tiff))

        XCTAssertEqual(document.contentType, .png)
        XCTAssertTrue(document.dataURI.hasPrefix("data:image/png;base64,"))
    }

    func testOCRSourceLeavesTextOnThePasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("OCRTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.setString("Hello", forType: .string)
        XCTAssertNil(OCRSource(pasteboard: pasteboard))
        XCTAssertFalse(OCRSource.isAvailable(in: pasteboard))

        pasteboard.clearContents()
        pasteboard.setData(Self.pngData(), forType: .png)
        guard case .imageData(let data) = OCRSource(pasteboard: pasteboard) else {
            return XCTFail("Expected image data from the pasteboard")
        }
        XCTAssertEqual(data, Self.pngData())

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try Self.pngData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        guard case .fileURL(let url) = OCRSource(pasteboard: pasteboard) else {
            return XCTFail("Expected an image file from the pasteboard")
        }
        XCTAssertEqual(url.standardizedFileURL, fileURL.standardizedFileURL)
    }

    private static func pngData() -> Data {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 4,
            pixelsHigh: 4,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        return representation?.representation(using: .png, properties: [:]) ?? Data()
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
