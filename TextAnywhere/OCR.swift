//
// Created by ktiays on 2026/10/22.
// Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum OCRModel: String, CaseIterable, Identifiable, Sendable {

    case glmOCR = "glm-ocr"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .glmOCR:
            "GLM-OCR"
        }
    }

    var provider: Provider {
        switch self {
        case .glmOCR:
            .bigModel
        }
    }
}

enum OCRSource: Sendable {

    case fileURL(URL)
    case imageData(Data)

    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
    ]

    static let draggedTypes: [NSPasteboard.PasteboardType] = [.fileURL] + imageTypes

    /// Reads an image or PDF from the pasteboard. Returns `nil` when the pasteboard carries
    /// plain text, so regular text keeps pasting as usual.
    init?(pasteboard: NSPasteboard) {
        if let fileURL = Self.recognizableFileURL(in: pasteboard) {
            self = .fileURL(fileURL)
            return
        }
        guard pasteboard.string(forType: .string) == nil,
              let type = pasteboard.availableType(from: Self.imageTypes),
              let data = pasteboard.data(forType: type) else {
            return nil
        }
        self = .imageData(data)
    }

    static func isAvailable(in pasteboard: NSPasteboard) -> Bool {
        recognizableFileURL(in: pasteboard) != nil
            || (pasteboard.string(forType: .string) == nil && pasteboard.availableType(from: imageTypes) != nil)
    }

    static func isRecognizableFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    private static func recognizableFileURL(in pasteboard: NSPasteboard) -> URL? {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return urls?.first { isRecognizableFile($0) }
    }
}

nonisolated struct OCRDocument: Sendable {

    private static let maximumImageByteCount = 10_000_000
    private static let maximumPDFByteCount = 50_000_000
    private static let maximumImagePixelSize = 4_096

    let data: Data
    let contentType: UTType

    var dataURI: String {
        "data:\(contentType.preferredMIMEType ?? "application/octet-stream");base64,\(data.base64EncodedString())"
    }

    init(source: OCRSource) throws {
        switch source {
        case .fileURL(let url):
            let data = try Data(contentsOf: url)
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                guard data.count <= Self.maximumPDFByteCount else {
                    throw ProviderError.invalidConfiguration("PDF files must be 50 MB or smaller.")
                }
                self.init(data: data, contentType: .pdf)
            } else {
                try self.init(imageData: data)
            }
        case .imageData(let data):
            try self.init(imageData: data)
        }
    }

    private init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    /// GLM-OCR accepts PNG and JPEG images up to 10 MB. Other formats and oversized images are
    /// re-encoded, downscaled, and rotated according to their EXIF orientation.
    private init(imageData: Data) throws {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(imageSource) as String? else {
            throw ProviderError.invalidConfiguration("The image couldn't be read.")
        }
        if let type = UTType(typeIdentifier),
           type == .png || type == .jpeg,
           imageData.count <= Self.maximumImageByteCount {
            self.init(data: imageData, contentType: type)
            return
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maximumImagePixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw ProviderError.invalidConfiguration("The image couldn't be read.")
        }
        if let png = Self.encode(image, as: .png), png.count <= Self.maximumImageByteCount {
            self.init(data: png, contentType: .png)
        } else if let jpeg = Self.encode(image, as: .jpeg, quality: 0.85),
                  jpeg.count <= Self.maximumImageByteCount {
            self.init(data: jpeg, contentType: .jpeg)
        } else {
            throw ProviderError.invalidConfiguration("The image is too large to recognize.")
        }
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

struct OCRConfiguration: Sendable {

    let endpoint: URL
    let model: OCRModel
    let apiKey: String

    init(baseURL: String, model: OCRModel, apiKey: String?) throws {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil else {
            throw ProviderError.invalidConfiguration(
                "Enter a valid base URL in Settings → Providers → \(model.provider.name)."
            )
        }
        guard let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw ProviderError.invalidConfiguration(
                "Set your \(model.provider.name) API key in Settings → Providers → \(model.provider.name)."
            )
        }
        endpoint = url.appending(path: "layout_parsing")
        self.model = model
        self.apiKey = apiKey
    }
}

struct OCRClient {

    var session: URLSession = .shared

    func recognizeText(in document: OCRDocument, configuration: OCRConfiguration) async throws -> String {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            LayoutParsingRequest(model: configuration.model.rawValue, file: document.dataURI)
        )

        let data = try await ProviderHTTPClient(session: session).send(request)
        guard let response = try? JSONDecoder().decode(LayoutParsingResponse.self, from: data) else {
            throw ProviderError.invalidResponse
        }
        let text = (response.markdown ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ProviderError.invalidConfiguration("No text was recognized.")
        }
        return text
    }
}

private struct LayoutParsingRequest: Encodable {
    let model: String
    let file: String
}

private struct LayoutParsingResponse: Decodable {
    let markdown: String?

    enum CodingKeys: String, CodingKey {
        case markdown = "md_results"
    }
}

enum ScreenCapture {

    private static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )

    static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Registers the app for Screen Recording and opens the matching privacy settings, since the
    /// system only prompts once.
    static func requestPermission() {
        guard !CGRequestScreenCaptureAccess(), let privacySettingsURL else { return }
        NSWorkspace.shared.open(privacySettingsURL)
    }

    /// Lets the user select a screen region with the system screenshot interface.
    /// Returns `nil` when the selection is cancelled.
    static func captureRegion() async throws -> Data? {
        guard hasPermission else {
            _ = CGRequestScreenCaptureAccess()
            throw ProviderError.invalidConfiguration(
                "Allow TextAnywhere in System Settings → Privacy & Security → Screen & System Audio Recording, then restart the app."
            )
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", fileURL.path]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        return try? Data(contentsOf: fileURL)
    }
}
