//
// Created by ktiays on 2026/10/22.
// Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum OCRMode: String, CaseIterable, Identifiable, Sendable {

    case recognizeOnly
    case recognizeAndTranslate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recognizeOnly:
            "Recognize Only"
        case .recognizeAndTranslate:
            "Recognize and Translate"
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

    private static let maximumPDFByteCount = 50_000_000
    private static let maximumDocumentByteCount = 20_000_000
    private static let maximumPDFPageCount = 100

    let images: [OCRImage]

    init(source: OCRSource) throws {
        switch source {
        case .fileURL(let url):
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                guard data.count <= Self.maximumPDFByteCount else {
                    throw ProviderError.invalidConfiguration("PDF files must be 50 MB or smaller.")
                }
                images = try Self.renderPDF(data)
            } else {
                images = [try OCRImage(imageData: data)]
            }
        case .imageData(let data):
            images = [try OCRImage(imageData: data)]
        }
    }

    private static func renderPDF(_ data: Data) throws -> [OCRImage] {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider), !document.isEncrypted,
              document.numberOfPages > 0 else {
            throw ProviderError.invalidConfiguration("The PDF couldn't be read or is password-protected.")
        }
        guard document.numberOfPages <= maximumPDFPageCount else {
            throw ProviderError.invalidConfiguration("Choose a PDF with 100 pages or fewer.")
        }

        var images: [OCRImage] = []
        var byteCount = 0
        for pageNumber in 1...document.numberOfPages {
            try Task.checkCancellation()
            let image = try autoreleasepool {
                guard let page = document.page(at: pageNumber) else {
                    throw ProviderError.invalidConfiguration("A PDF page couldn't be read.")
                }
                return try OCRImage(page: page)
            }
            byteCount += image.data.count
            guard byteCount <= maximumDocumentByteCount else {
                throw ProviderError.invalidConfiguration(
                    "The rendered PDF is too large to recognize in one request. Choose a smaller PDF."
                )
            }
            images.append(image)
        }
        return images
    }
}

nonisolated struct OCRImage: Sendable {

    private static let maximumImageByteCount = 5_000_000
    private static let maximumImagePixelSize = 4_096

    let data: Data
    let contentType: UTType

    var mimeType: String {
        contentType.preferredMIMEType ?? "image/png"
    }

    var dataURI: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(imageData: Data) throws {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(imageSource) as String? else {
            throw ProviderError.invalidConfiguration("The image couldn't be read.")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        if let type = UTType(typeIdentifier),
           type == .png || type == .jpeg,
           imageData.count <= Self.maximumImageByteCount,
           max(width, height) <= Self.maximumImagePixelSize, orientation == 1 {
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
        try self.init(image: image)
    }

    init(page: CGPDFPage) throws {
        let bounds = page.getBoxRect(.cropBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            throw ProviderError.invalidConfiguration("A PDF page has an invalid size.")
        }
        let scale = min(2, CGFloat(Self.maximumImagePixelSize) / max(bounds.width, bounds.height))
        let isRotated = page.rotationAngle % 180 != 0
        let width = Int(ceil((isRotated ? bounds.height : bounds.width) * scale))
        let height = Int(ceil((isRotated ? bounds.width : bounds.height) * scale))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ProviderError.invalidConfiguration("A PDF page couldn't be rendered.")
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else {
            throw ProviderError.invalidConfiguration("A PDF page couldn't be rendered.")
        }
        try self.init(image: image)
    }

    private init(image: CGImage) throws {
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
