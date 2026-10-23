//
//  Created by ktiays on 2026/10/24.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation
import XCTest
@testable import TextAnywhere

final class SoftwareUpdateTests: XCTestCase {

    override func tearDown() {
        ReleaseStubURLProtocol.response = nil
        super.tearDown()
    }

    func testSemanticVersionParsing() throws {
        XCTAssertEqual(SemanticVersion("v1.14.0")?.description, "1.14.0")
        XCTAssertEqual(SemanticVersion("1.13")?.description, "1.13.0")
        XCTAssertEqual(SemanticVersion("v2.0.0-beta.1")?.description, "2.0.0")
        XCTAssertEqual(SemanticVersion("1.2.3+build.5")?.description, "1.2.3")
        XCTAssertNil(SemanticVersion("1"))
        XCTAssertNil(SemanticVersion("1.2.3.4"))
        XCTAssertNil(SemanticVersion("1..3"))
        XCTAssertNil(SemanticVersion("1.a.3"))
        XCTAssertNil(SemanticVersion(""))
    }

    func testSemanticVersionOrdering() throws {
        let versions = ["1.13", "1.9.9", "1.13.1", "2.0.0", "1.14.0"].compactMap(SemanticVersion.init)
        XCTAssertEqual(versions.sorted().map(\.description), ["1.9.9", "1.13.0", "1.13.1", "1.14.0", "2.0.0"])
        XCTAssertEqual(SemanticVersion("1.13"), SemanticVersion("v1.13.0"))
    }

    func testNewerReleaseIsOfferedWithItsArchive() async throws {
        ReleaseStubURLProtocol.response = (200, releaseJSON(tag: "v1.14.0", assetNames: ["TextAnywhere-1.14.0.zip"]))

        let update = try await checker().availableUpdate(newerThan: try XCTUnwrap(SemanticVersion("1.13")))

        XCTAssertEqual(update?.version.description, "1.14.0")
        XCTAssertEqual(
            update?.archiveURL.absoluteString,
            "https://github.com/ktiays/TextAnywhere/releases/download/v1.14.0/TextAnywhere-1.14.0.zip"
        )
        XCTAssertEqual(
            update?.releasePageURL.absoluteString,
            "https://github.com/ktiays/TextAnywhere/releases/tag/v1.14.0"
        )
    }

    func testSameOrOlderReleaseIsNotOffered() async throws {
        ReleaseStubURLProtocol.response = (200, releaseJSON(tag: "v1.13.0", assetNames: ["TextAnywhere-1.13.0.zip"]))

        let update = try await checker().availableUpdate(newerThan: try XCTUnwrap(SemanticVersion("1.13.0")))

        XCTAssertNil(update)
    }

    func testMissingReleaseIsTreatedAsUpToDate() async throws {
        ReleaseStubURLProtocol.response = (404, #"{"message":"Not Found"}"#)

        let update = try await checker().availableUpdate(newerThan: try XCTUnwrap(SemanticVersion("1.13.0")))

        XCTAssertNil(update)
    }

    func testReleaseWithoutArchiveFails() async throws {
        ReleaseStubURLProtocol.response = (200, releaseJSON(tag: "v1.14.0", assetNames: ["notes.txt"]))

        do {
            _ = try await checker().availableUpdate(newerThan: try XCTUnwrap(SemanticVersion("1.13.0")))
            XCTFail("Expected missingArchive.")
        } catch SoftwareUpdateError.missingArchive {
        }
    }

    func testRateLimitedResponseFails() async throws {
        ReleaseStubURLProtocol.response = (403, #"{"message":"API rate limit exceeded"}"#)

        do {
            _ = try await checker().availableUpdate(newerThan: try XCTUnwrap(SemanticVersion("1.13.0")))
            XCTFail("Expected unexpectedStatusCode.")
        } catch SoftwareUpdateError.unexpectedStatusCode(let statusCode) {
            XCTAssertEqual(statusCode, 403)
        }
    }

    func testDevelopmentSignedAppFailsVerification() async throws {
        do {
            try await UpdateInstaller.verifySignature(
                of: Bundle.main.bundleURL,
                bundleIdentifier: "me.ktiays.TextAnywhere",
                teamIdentifier: "V8K4KDZ2JN"
            )
            XCTFail("A development-signed app must not pass Developer ID verification.")
        } catch SoftwareUpdateError.invalidSignature {
        }
    }

    private func checker() -> UpdateChecker {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseStubURLProtocol.self]
        return UpdateChecker(
            latestReleaseURL: UpdateChecker.latestReleaseURL,
            session: URLSession(configuration: configuration)
        )
    }

    private func releaseJSON(tag: String, assetNames: [String]) -> String {
        let assets = assetNames.map { name in
            #"{"name":"\#(name)","browser_download_url":"https://github.com/ktiays/TextAnywhere/releases/download/\#(tag)/\#(name)"}"#
        }
        return #"{"tag_name":"\#(tag)","html_url":"https://github.com/ktiays/TextAnywhere/releases/tag/\#(tag)","assets":[\#(assets.joined(separator: ","))]}"#
    }
}

private final class ReleaseStubURLProtocol: URLProtocol {

    nonisolated(unsafe) static var response: (statusCode: Int, body: String)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let stub = Self.response,
              let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
