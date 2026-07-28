import Foundation

public protocol MailSending: Sendable {
    func send(messageFile: URL, size: Int64, accessToken: String) async throws -> MailSendReceipt
}

public struct MailSendReceipt: Codable, Sendable, Equatable {
    public let messageID: String
    public let threadID: String?

    public init(messageID: String, threadID: String? = nil) {
        self.messageID = messageID
        self.threadID = threadID
    }
}

public protocol TokenProviding: Sendable {
    func validAccessToken(for accountID: GmailAccountID) async throws -> String
}

public protocol OAuthCoordinating: Sendable {
    func authorize(
        clientID: String,
        redirectScheme: String
    ) async throws -> GmailAccountSummary
    func remove(accountID: GmailAccountID, revoke: Bool) async throws
}

public protocol FileAnalyzing: Sendable {
    func analyze(urls: [URL], policy: AnalysisPolicy) async throws -> [AttachmentAnalysis]
}

public protocol EmailDraftGenerating: Sendable {
    func streamDraft(
        request: DraftGenerationRequest
    ) -> AsyncThrowingStream<GeneratedDraftSnapshot, Error>
}

public protocol RecipientRanking: Sendable {
    func ranked(
        recipients: [RecipientProfile],
        excludingOwnAddresses: Set<String>,
        limit: Int,
        now: Date
    ) -> [RecipientProfile]
}

public protocol TemporaryFileManaging: Sendable {
    func makeTemporaryFile(extension fileExtension: String?) async throws -> URL
    func register(_ url: URL) async
    func remove(_ url: URL) async
    func cleanExpiredFiles(olderThan: TimeInterval) async
}

public protocol Clock: Sendable {
    func now() -> Date
}

public protocol UUIDGenerating: Sendable {
    func makeUUID() -> UUID
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

public struct SystemUUIDGenerator: UUIDGenerating {
    public init() {}
    public func makeUUID() -> UUID { UUID() }
}
