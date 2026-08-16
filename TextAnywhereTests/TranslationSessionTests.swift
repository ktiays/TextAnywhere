//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation
import XCTest
@testable import TextAnywhere

final class TranslationSessionTests: XCTestCase {

    func testPrimaryTranslateAndPasteCopiesTranslationBeforeInsertingAndCallsSuccess() async throws {
        let environment = makeEnvironment(adapterResult: .success("Bonjour"))
        let insertionStarted = expectation(description: "Insertion started")
        let success = expectation(description: "Successful insertion")
        environment.session.setActions(
            onInsertionStarted: {
                insertionStarted.fulfill()
            },
            onSuccessfulInsertion: {
                success.fulfill()
            },
            onInsertionFailed: {},
            onDismiss: {}
        )
        environment.session.draft = "Hello"
        environment.session.selectTarget(Self.targetApplication)

        environment.session.performPrimaryAction()
        await fulfillment(of: [insertionStarted, success], timeout: 1, enforceOrder: true)

        XCTAssertEqual(environment.insertionService.insertedText, "Bonjour")
        XCTAssertEqual(environment.insertionService.pasteboardTextAtInsertion, "Bonjour")
        XCTAssertEqual(environment.session.draft, "")
        XCTAssertEqual(environment.pasteboard.text, "Bonjour")
    }

    func testInsertionFailureCopiesTranslationAndKeepsDraft() async throws {
        let environment = makeEnvironment(
            adapterResult: .success("Bonjour"),
            insertionError: TextInsertionError.unsupportedTextElement
        )
        let insertionFailed = expectation(description: "Insertion failed")
        environment.session.setActions(
            onInsertionStarted: {},
            onSuccessfulInsertion: {},
            onInsertionFailed: {
                insertionFailed.fulfill()
            },
            onDismiss: {}
        )
        environment.session.draft = "Hello"
        environment.session.selectTarget(Self.targetApplication)

        environment.session.translateAndPaste()
        await fulfillment(of: [insertionFailed], timeout: 1)

        XCTAssertEqual(environment.pasteboard.text, "Bonjour")
        XCTAssertEqual(environment.session.draft, "Hello")
        guard case .message(let message, let isError) = environment.session.state else {
            return XCTFail("Expected a fallback message")
        }
        XCTAssertTrue(isError)
        XCTAssertTrue(message.contains("does not expose a writable text selection"))
        XCTAssertTrue(message.contains("Paste"))
    }

    func testProviderFailurePreservesDraft() async throws {
        let environment = makeEnvironment(
            adapterResult: .failure(ProviderError.httpStatus(401, "Invalid key"))
        )
        environment.session.draft = "Hello"
        environment.session.selectTarget(Self.targetApplication)

        environment.session.translateAndPaste()
        try await waitUntil {
            if case .message = environment.session.state { return true }
            return false
        }

        XCTAssertEqual(environment.session.draft, "Hello")
        XCTAssertNil(environment.insertionService.insertedText)
        XCTAssertNil(environment.pasteboard.text)
    }

    func testMissingTargetPreventsProviderCall() {
        let adapter = FakeAdapter(result: .success("Bonjour"))
        let environment = makeEnvironment(adapter: adapter)
        environment.session.draft = "Hello"

        environment.session.translateAndPaste()

        XCTAssertEqual(adapter.translationCallCount, 0)
        guard case .message(_, let isError) = environment.session.state else {
            return XCTFail("Expected a validation message")
        }
        XCTAssertTrue(isError)
    }

    func testConfiguredPrimaryActionPastesDraftWithoutCallingProvider() async {
        let adapter = FakeAdapter(result: .success("Bonjour"))
        let environment = makeEnvironment(adapter: adapter)
        environment.settings.primaryButtonAction = .paste
        let success = expectation(description: "Successful insertion")
        environment.session.setActions(
            onInsertionStarted: {},
            onSuccessfulInsertion: {
                success.fulfill()
            },
            onInsertionFailed: {},
            onDismiss: {}
        )
        environment.session.draft = "Hello"
        environment.session.selectTarget(Self.targetApplication)

        environment.session.performPrimaryAction()
        await fulfillment(of: [success], timeout: 1)

        XCTAssertEqual(adapter.translationCallCount, 0)
        XCTAssertEqual(environment.insertionService.insertedText, "Hello")
        XCTAssertEqual(environment.insertionService.pasteboardTextAtInsertion, "Hello")
        XCTAssertEqual(environment.pasteboard.text, "Hello")
        XCTAssertEqual(environment.session.draft, "")
    }

    func testPrimaryButtonTitleReflectsConfiguredAction() {
        let environment = makeEnvironment(adapterResult: .success("Bonjour"))

        XCTAssertEqual(environment.session.primaryButtonTitle, "Translate and Paste")

        environment.settings.primaryButtonAction = .paste
        XCTAssertEqual(environment.session.primaryButtonTitle, "Paste")
    }

    func testTranslationActionsAreUnavailableWithoutAnEnabledProvider() {
        let environment = makeEnvironment(adapterResult: .success("Bonjour"))
        environment.settings.setProviderEnabled(false, for: .bailian)
        environment.session.draft = "Hello"

        XCTAssertFalse(environment.session.hasAvailableProvider)
        XCTAssertFalse(environment.session.canTranslate)
        XCTAssertTrue(environment.session.canPaste)
    }

    private func makeEnvironment(
        adapterResult: Result<String, Error>,
        insertionError: Error? = nil
    ) -> TestEnvironment {
        makeEnvironment(adapter: FakeAdapter(result: adapterResult), insertionError: insertionError)
    }

    private func makeEnvironment(
        adapter: FakeAdapter,
        insertionError: Error? = nil
    ) -> TestEnvironment {
        let suiteName = "TranslationSessionTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.selectedProviderID = .bailian
        settings.setBaseURL("https://example.com/v1", for: .bailian)
        settings.setModelID("qwen-test", for: .bailian)

        let credentials = FakeCredentialStore(apiKey: "test-key")
        let pasteboard = FakePasteboard()
        let insertionService = FakeInsertionService(error: insertionError, pasteboard: pasteboard)
        let session = TranslationSession(
            settings: settings,
            credentials: credentials,
            insertionService: insertionService,
            pasteboard: pasteboard,
            applicationTracker: ApplicationTracker(),
            adapterFactory: { _ in adapter }
        )

        return TestEnvironment(
            settings: settings,
            session: session,
            insertionService: insertionService,
            pasteboard: pasteboard
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static let targetApplication = TargetApplication(
        processIdentifier: 123,
        bundleIdentifier: "com.example.Target",
        localizedName: "Target"
    )
}

private struct TestEnvironment {
    let settings: AppSettings
    let session: TranslationSession
    let insertionService: FakeInsertionService
    let pasteboard: FakePasteboard
}

private final class FakeAdapter: TranslationProviderAdapter {

    let result: Result<String, Error>
    private(set) var translationCallCount = 0

    init(result: Result<String, Error>) {
        self.result = result
    }

    func fetchModels(configuration: ProviderConfiguration) async throws -> [ModelDescriptor] {
        []
    }

    func translate(
        _ request: TranslationRequest,
        configuration: ProviderConfiguration
    ) async throws -> String {
        translationCallCount += 1
        return try result.get()
    }
}

private final class FakeCredentialStore: CredentialStore {

    private var apiKey: String?

    init(apiKey: String?) {
        self.apiKey = apiKey
    }

    func apiKey(for providerID: ProviderIdentifier) throws -> String? {
        apiKey
    }

    func setAPIKey(_ apiKey: String, for providerID: ProviderIdentifier) throws {
        self.apiKey = apiKey
    }
}

private final class FakeInsertionService: TextInsertionService {

    var isTrusted = true
    private(set) var insertedText: String?
    private(set) var pasteboardTextAtInsertion: String?
    let error: Error?
    let pasteboard: FakePasteboard

    init(error: Error?, pasteboard: FakePasteboard) {
        self.error = error
        self.pasteboard = pasteboard
    }

    func requestPermission() {}

    func captureTarget(in application: TargetApplication, window: TargetWindow?) -> CapturedTextTarget {
        CapturedTextTarget(application: application, window: window)
    }

    func insert(_ text: String, into target: CapturedTextTarget) async throws {
        pasteboardTextAtInsertion = pasteboard.text
        if let error { throw error }
        insertedText = text
    }
}

private final class FakePasteboard: PasteboardWriting {

    private(set) var text: String?

    func copy(_ text: String) {
        self.text = text
    }
}
