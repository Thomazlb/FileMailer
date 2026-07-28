import FileMailerDomain
import Foundation
@testable import GoogleDrive
import XCTest

final class GoogleDrivePermissionTests: XCTestCase {
    func testRecipientPermissionsArePrivateDeduplicatedAndExpiring() async throws {
        let recorder = DriveRequestRecorder()
        let session = stubSession { request in
            recorder.append(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"id":"permission-id"}"#.utf8))
        }
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = GoogleDriveTransferCoordinator(
            client: GoogleDriveClient(session: session),
            tokenProvider: StaticTokenProvider(),
            store: try DriveTransferStore(applicationSupportDirectory: root)
        )
        let recipients = [
            try EmailAddress("alice@example.test"),
            try EmailAddress("ALICE@example.test"),
            try EmailAddress("bob@example.test")
        ]
        let expiresAt = Date(timeIntervalSince1970: 1_900_000_000)

        try await coordinator.grantRecipientReaderAccess(
            to: DriveFileReference(
                id: "file-id",
                webViewURL: try XCTUnwrap(URL(string: "https://drive.google.com/file/d/file-id/view")),
                accountID: GmailAccountID(rawValue: "account")
            ),
            recipients: recipients,
            expiresAt: expiresAt
        )

        let permissionBody = GoogleDriveClient.userReaderPermissionBody(
            recipient: try EmailAddress("alice@example.test"),
            expiresAt: expiresAt
        )
        XCTAssertEqual(permissionBody["type"] as? String, "user")
        XCTAssertEqual(permissionBody["role"] as? String, "reader")
        XCTAssertEqual(permissionBody["emailAddress"] as? String, "alice@example.test")
        XCTAssertNotNil(permissionBody["expirationTime"] as? String)
        XCTAssertNil(permissionBody["allowFileDiscovery"])

        let requests = recorder.requests
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST")
            let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            XCTAssertEqual(
                components.queryItems?.first(where: { $0.name == "sendNotificationEmail" })?.value,
                "false"
            )
        }
    }

    func testFailedPermissionGrantRollsBackEarlierRecipientPermissions() async throws {
        let recorder = DriveRequestRecorder()
        let session = stubSession { request in
            recorder.append(request)
            let requestCount = recorder.requests.count
            let status = request.httpMethod == "POST" && requestCount == 2 ? 403 : 200
            let body = status == 200 ? Data(#"{"id":"permission-one"}"#.utf8) : Data()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body)
        }
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = GoogleDriveTransferCoordinator(
            client: GoogleDriveClient(session: session),
            tokenProvider: StaticTokenProvider(),
            store: try DriveTransferStore(applicationSupportDirectory: root)
        )
        let file = DriveFileReference(
            id: "file-id",
            webViewURL: try XCTUnwrap(URL(string: "https://drive.google.com/file/d/file-id/view")),
            accountID: GmailAccountID(rawValue: "account")
        )

        do {
            try await coordinator.grantRecipientReaderAccess(
                to: file,
                recipients: [
                    try EmailAddress("alice@example.test"),
                    try EmailAddress("bob@example.test")
                ],
                expiresAt: nil
            )
            XCTFail("A failed recipient permission should abort the share")
        } catch {
            guard case GoogleDriveError.sharingNotAllowed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let requests = recorder.requests
        XCTAssertEqual(requests.map { $0.httpMethod ?? "" }, ["POST", "POST", "DELETE"])
        XCTAssertTrue(requests[2].url?.path.hasSuffix("/permissions/permission-one") == true)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func stubSession(
        _ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        DriveStubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DriveStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

}

private actor StaticTokenProvider: TokenProviding {
    func validAccessToken(for accountID: GmailAccountID) async throws -> String { "test-token" }
}

private final class DriveRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func append(_ request: URLRequest) {
        lock.lock()
        values.append(request)
        lock.unlock()
    }
}

private final class DriveStubURLProtocol: URLProtocol, @unchecked Sendable {
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
