//
//  Created by ktiays on 2026/10/24.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import Foundation
import Security

struct SemanticVersion: Comparable, CustomStringConvertible {

    let major: Int
    let minor: Int
    let patch: Int

    /// Accepts `1.2.3`, `v1.2.3`, and `1.2`. Pre-release and build suffixes are ignored, because
    /// only stable releases are offered as updates.
    init?(_ string: String) {
        var core = string.hasPrefix("v") ? string.dropFirst() : Substring(string)
        if let suffixStart = core.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            core = core[..<suffixStart]
        }
        let components = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(components.count),
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else {
            return nil
        }
        let numbers = components.compactMap { Int($0) }
        guard numbers.count == components.count else { return nil }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers.count == 3 ? numbers[2] : 0
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct GitHubRelease: Decodable {

    struct Asset: Decodable {

        let name: String
        let downloadURL: URL

        private enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let pageURL: URL
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
        case assets
    }
}

struct AvailableUpdate: Equatable {

    let version: SemanticVersion
    let releasePageURL: URL
    let archiveURL: URL
}

enum SoftwareUpdateError: LocalizedError {

    case invalidResponse
    case unexpectedStatusCode(Int)
    case missingArchive
    case translocated
    case installLocationNotWritable(URL)
    case extractionFailed
    case invalidArchiveContents
    case invalidSignature(String)
    case versionMismatch(expected: SemanticVersion, found: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub returned a response that couldn't be read."
        case .unexpectedStatusCode(let statusCode):
            "GitHub returned HTTP status \(statusCode)."
        case .missingArchive:
            "The latest release doesn't include a downloadable app."
        case .translocated:
            "TextAnywhere is running from a temporary location. Move it to the Applications folder, open it again, and retry."
        case .installLocationNotWritable(let directoryURL):
            "TextAnywhere can't replace itself in “\(directoryURL.path)” because you don't have permission to write there."
        case .extractionFailed:
            "The downloaded update couldn't be unpacked."
        case .invalidArchiveContents:
            "The downloaded update doesn't contain exactly one app."
        case .invalidSignature(let reason):
            "The downloaded update isn't signed by the TextAnywhere developer (\(reason))."
        case .versionMismatch(let expected, let found):
            "The downloaded app is version \(found), but version \(expected) was expected."
        }
    }
}

struct UpdateChecker {

    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/ktiays/TextAnywhere/releases/latest"
    )

    let latestReleaseURL: URL?
    let session: URLSession

    init(latestReleaseURL: URL? = Self.latestReleaseURL, session: URLSession = .shared) {
        self.latestReleaseURL = latestReleaseURL
        self.session = session
    }

    /// Returns `nil` when the latest stable release isn't newer than `currentVersion`, or when the
    /// repository has no stable release yet.
    func availableUpdate(newerThan currentVersion: SemanticVersion) async throws -> AvailableUpdate? {
        guard let latestReleaseURL else { throw SoftwareUpdateError.invalidResponse }

        var request = URLRequest(url: latestReleaseURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 404 {
                return nil
            }
            guard httpResponse.statusCode == 200 else {
                throw SoftwareUpdateError.unexpectedStatusCode(httpResponse.statusCode)
            }
        }

        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw SoftwareUpdateError.invalidResponse
        }
        guard let version = SemanticVersion(release.tagName) else {
            throw SoftwareUpdateError.invalidResponse
        }
        guard version > currentVersion else { return nil }
        guard let archive = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) else {
            throw SoftwareUpdateError.missingArchive
        }

        return AvailableUpdate(
            version: version,
            releasePageURL: release.pageURL,
            archiveURL: archive.downloadURL
        )
    }
}

struct UpdateInstaller {

    private static let teamIdentifier = "V8K4KDZ2JN"

    let bundleURL: URL
    let bundleIdentifier: String
    let session: URLSession

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "me.ktiays.TextAnywhere",
        session: URLSession = .shared
    ) {
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.session = session
    }

    func validateInstallLocation() throws {
        if bundleURL.path.contains("/AppTranslocation/") {
            throw SoftwareUpdateError.translocated
        }
        let fileManager = FileManager.default
        let parentURL = bundleURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parentURL.path),
              fileManager.isWritableFile(atPath: bundleURL.path) else {
            throw SoftwareUpdateError.installLocationNotWritable(parentURL)
        }
    }

    /// Downloads, unpacks, and verifies the update next to the installed app, so the final swap
    /// is a rename on the same volume. The caller owns the returned staging directory.
    func stageUpdate(_ update: AvailableUpdate) async throws -> (stagingDirectoryURL: URL, appURL: URL) {
        let stagingDirectoryURL = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: bundleURL,
            create: true
        )
        do {
            let appURL = try await stageUpdate(update, in: stagingDirectoryURL)
            return (stagingDirectoryURL, appURL)
        } catch {
            try? FileManager.default.removeItem(at: stagingDirectoryURL)
            throw error
        }
    }

    /// Atomically swaps the staged app into place. The running process keeps executing from the
    /// old, now unlinked, files until it quits.
    func install(stagedAppURL: URL) throws {
        _ = try FileManager.default.replaceItemAt(bundleURL, withItemAt: stagedAppURL)
    }

    /// Starts a detached shell that waits for this process to exit and then opens the new app.
    func relaunch() throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [
            "-c",
            #"while /bin/kill -0 "$0" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$1""#,
            String(ProcessInfo.processInfo.processIdentifier),
            bundleURL.path,
        ]
        try process.run()
        NSApp.terminate(nil)
    }

    private func stageUpdate(_ update: AvailableUpdate, in stagingDirectoryURL: URL) async throws -> URL {
        let (downloadedURL, response) = try await session.download(from: update.archiveURL)
        let archiveURL = stagingDirectoryURL.appending(path: "update.zip")
        try FileManager.default.moveItem(at: downloadedURL, to: archiveURL)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SoftwareUpdateError.unexpectedStatusCode(httpResponse.statusCode)
        }

        let extractionURL = stagingDirectoryURL.appending(path: "Extracted", directoryHint: .isDirectory)
        let status = try await Self.runProcess(
            URL(filePath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archiveURL.path, extractionURL.path]
        )
        guard status == 0 else { throw SoftwareUpdateError.extractionFailed }

        let appURLs = try FileManager.default
            .contentsOfDirectory(at: extractionURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard appURLs.count == 1, let appURL = appURLs.first else {
            throw SoftwareUpdateError.invalidArchiveContents
        }

        try await Self.verifySignature(
            of: appURL,
            bundleIdentifier: bundleIdentifier,
            teamIdentifier: Self.teamIdentifier
        )

        let foundVersion = Bundle(url: appURL)?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard SemanticVersion(foundVersion) == update.version else {
            throw SoftwareUpdateError.versionMismatch(expected: update.version, found: foundVersion)
        }
        return appURL
    }

    /// Requires a valid, notarized Developer ID Application signature from our team for the same
    /// bundle identifier, covering every architecture and nested bundle.
    @concurrent
    nonisolated static func verifySignature(
        of appURL: URL,
        bundleIdentifier: String,
        teamIdentifier: String
    ) async throws {
        let requirementText = """
            anchor apple generic \
            and identifier "\(bundleIdentifier)" \
            and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
            and certificate leaf[subject.OU] = "\(teamIdentifier)" \
            and notarized
            """

        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else {
            throw SoftwareUpdateError.invalidSignature(Self.message(for: status))
        }

        var requirement: SecRequirement?
        status = SecRequirementCreateWithString(requirementText as CFString, [], &requirement)
        guard status == errSecSuccess, let requirement else {
            throw SoftwareUpdateError.invalidSignature(Self.message(for: status))
        }

        let flags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode
        )
        status = SecStaticCodeCheckValidity(staticCode, flags, requirement)
        guard status == errSecSuccess else {
            throw SoftwareUpdateError.invalidSignature(Self.message(for: status))
        }
    }

    nonisolated private static func message(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)."
    }

    private static func runProcess(_ executableURL: URL, arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
