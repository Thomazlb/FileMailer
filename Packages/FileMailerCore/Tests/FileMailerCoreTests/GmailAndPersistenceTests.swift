import FileMailerDomain
import GmailAPI
import Persistence
import XCTest

final class GmailAndPersistenceTests: XCTestCase {
    func testGmailStatusMappingAndMalformedResponse() async throws {
        let file = temporaryMessage()
        defer { try? FileManager.default.removeItem(at: file) }
        let session = stubSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"error":{"message":"admin policy"}}"#.utf8))
        }
        do {
            _ = try await GmailMailSender(session: session).send(
                messageFile: file,
                size: 1,
                accessToken: "test-token"
            )
            XCTFail("403 should fail")
        } catch {
            guard case GmailSendError.administratorPolicy = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let malformedSession = stubSession { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data("not-json".utf8)
            )
        }
        do {
            _ = try await GmailMailSender(session: malformedSession).send(
                messageFile: file,
                size: 1,
                accessToken: "test-token"
            )
            XCTFail("Malformed response should fail")
        } catch {
            guard case GmailSendError.malformedResponse = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testSingleRetryAfter401() async throws {
        let sender = RetrySender()
        let provider = SequenceTokenProvider()
        let file = temporaryMessage()
        defer { try? FileManager.default.removeItem(at: file) }
        let receipt = try await GmailUploadCoordinator(
            sender: sender,
            tokenProvider: provider
        ).send(
            messageFile: file,
            size: 1,
            accountID: GmailAccountID(rawValue: "sub")
        )
        XCTAssertEqual(receipt.messageID, "success")
        let senderCount = await sender.count
        let providerCount = await provider.count
        XCTAssertEqual(senderCount, 2)
        XCTAssertEqual(providerCount, 2)
    }

    func testTimeoutIsAmbiguousAndIsNotRetriedBySender() async throws {
        let file = temporaryMessage()
        defer { try? FileManager.default.removeItem(at: file) }
        let session = stubSession { _ in
            throw URLError(.timedOut)
        }
        do {
            _ = try await GmailMailSender(session: session).send(
                messageFile: file,
                size: 1,
                accessToken: "synthetic-token"
            )
            XCTFail("Timeout should fail")
        } catch {
            guard case GmailSendError.ambiguousTimeout = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testQuotaResponseMapsToTypedError() async throws {
        let file = temporaryMessage()
        defer { try? FileManager.default.removeItem(at: file) }
        let session = stubSession { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        do {
            _ = try await GmailMailSender(session: session).send(
                messageFile: file,
                size: 1,
                accessToken: "synthetic-token"
            )
            XCTFail("Quota response should fail")
        } catch {
            guard case GmailSendError.quota = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @MainActor
    func testSuccessfulSendUpdatesRankingAndFailureDoesNot() throws {
        let controller = try PersistenceController(inMemory: true)
        let recipient = RecipientProfile(
            displayName: "Alice",
            email: "alice@example.test"
        )
        try controller.upsert(recipient: recipient)
        try controller.recordSuccessfulSend(
            accountID: GmailAccountID(rawValue: "sub"),
            recipients: [try EmailAddress("alice@example.test")],
            attachments: []
        )
        XCTAssertEqual(try controller.recipients().first?.localSendCount, 1)
        XCTAssertEqual(try controller.recipients().first?.sentLast30Days, 1)
    }

    @MainActor
    func testSwiftDataSchemaInitializesInMemory() throws {
        let controller = try PersistenceController(inMemory: true)
        XCTAssertEqual(try controller.settings().visibleRecipientCount, 5)
        XCTAssertFalse(try controller.settings().autosaveDrafts)
        XCTAssertTrue(try controller.recipients().isEmpty)
    }

    @MainActor
    func testPendingDraftRoundTripUsesBookmarkAndCanBeDeleted() throws {
        let controller = try PersistenceController(inMemory: true)
        let attachment = temporaryMessage()
        defer { try? FileManager.default.removeItem(at: attachment) }
        let draft = ComposeDraft(
            senderID: GmailAccountID(rawValue: "sub"),
            to: [try EmailAddress("alice@example.test")],
            subject: "Visible edit",
            body: "Current body",
            attachments: [ComposeAttachment(url: attachment, size: 1)],
            userRevision: 7
        )
        try controller.savePendingDraft(draft)
        let restored = try XCTUnwrap(controller.pendingDrafts().first)
        XCTAssertEqual(restored.id, draft.id)
        XCTAssertEqual(restored.subject, "Visible edit")
        XCTAssertEqual(restored.body, "Current body")
        XCTAssertEqual(
            restored.attachments.first?.url.resolvingSymlinksInPath(),
            attachment.resolvingSymlinksInPath()
        )
        try controller.deletePendingDraft(id: draft.id)
        XCTAssertTrue(try controller.pendingDrafts().isEmpty)
    }

    @MainActor
    func testDeletingAllPendingDraftsClearsEveryDraft() throws {
        let controller = try PersistenceController(inMemory: true)
        try controller.savePendingDraft(ComposeDraft(subject: "First"))
        try controller.savePendingDraft(ComposeDraft(subject: "Second"))
        XCTAssertEqual(try controller.pendingDrafts().count, 2)
        try controller.deleteAllPendingDrafts()
        XCTAssertTrue(try controller.pendingDrafts().isEmpty)
    }

    @MainActor
    func testRemovingAccountClearsPreferredSenderOnly() throws {
        let controller = try PersistenceController(inMemory: true)
        let accountID = GmailAccountID(rawValue: "subject-1")
        try controller.upsert(
            account: GmailAccountSummary(
                id: accountID,
                email: "sender@example.test",
                isDefault: true,
                grantedScopes: [],
                authStatus: .connected
            )
        )
        let recipient = RecipientProfile(
            displayName: "Alice",
            email: "alice@example.test",
            preferredSenderID: accountID,
            localSendCount: 3
        )
        try controller.upsert(recipient: recipient)
        try controller.removeAccountMetadata(accountID: accountID)
        let stored = try XCTUnwrap(controller.recipients().first)
        XCTAssertNil(stored.preferredSenderID)
        XCTAssertEqual(stored.localSendCount, 3)
    }

    private func temporaryMessage() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        return url
    }

    private func stubSession(
        _ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        StubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor RetrySender: MailSending {
    private(set) var count = 0

    func send(messageFile: URL, size: Int64, accessToken: String) async throws -> MailSendReceipt {
        count += 1
        if count == 1 { throw GmailSendError.authenticationExpired }
        return MailSendReceipt(messageID: "success")
    }
}

private actor SequenceTokenProvider: TokenProviding {
    private(set) var count = 0

    func validAccessToken(for accountID: GmailAccountID) async throws -> String {
        count += 1
        return "token-\(count)"
    }
}
