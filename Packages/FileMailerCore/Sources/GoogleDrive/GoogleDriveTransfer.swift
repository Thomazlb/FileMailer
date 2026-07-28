import FileMailerDomain
import Foundation

public enum GoogleDriveError: Error, LocalizedError, Sendable {
    case authorizationRequired
    case missingRecipients
    case fileAccessLost
    case invalidExpiry
    case fileNotFound
    case sharingNotAllowed
    case administratorPolicy
    case quota
    case networkUnavailable
    case malformedResponse
    case server(status: Int)

    public var errorDescription: String? {
        switch self {
        case .authorizationRequired:
            "Autorisez Google Drive pour ce compte avant d’envoyer ce lien."
        case .missingRecipients:
            "Ajoutez au moins un destinataire avant de créer un lien Google Drive."
        case .fileAccessLost:
            "Le fichier à envoyer n’est plus accessible."
        case .invalidExpiry:
            "La date d’expiration Drive doit être comprise entre maintenant et un an."
        case .fileNotFound:
            "Le fichier ou le dossier FileMailer n’existe plus dans Google Drive."
        case .sharingNotAllowed:
            "Google Drive ne permet pas de rendre ce fichier accessible par lien."
        case .administratorPolicy:
            "L’administrateur Google Workspace bloque l’utilisation de Google Drive par FileMailer."
        case .quota:
            "Le quota Google Drive est temporairement dépassé."
        case .networkUnavailable:
            "Le réseau est indisponible."
        case .malformedResponse:
            "La réponse Google Drive est illisible."
        case let .server(status):
            "Google Drive a répondu avec l’erreur \(status)."
        }
    }
}

public struct DriveTransferRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let accountID: GmailAccountID
    public let fileID: String
    public let displayName: String
    public let action: DriveCleanupAction
    public let dueAt: Date
    public let createdAt: Date
    public var lastFailureDescription: String?
    public var lastAttemptAt: Date?

    public init(
        id: UUID = UUID(),
        accountID: GmailAccountID,
        fileID: String,
        displayName: String,
        action: DriveCleanupAction,
        dueAt: Date,
        createdAt: Date = Date(),
        lastFailureDescription: String? = nil,
        lastAttemptAt: Date? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.fileID = fileID
        self.displayName = displayName
        self.action = action
        self.dueAt = dueAt
        self.createdAt = createdAt
        self.lastFailureDescription = lastFailureDescription
        self.lastAttemptAt = lastAttemptAt
    }
}

public actor DriveTransferStore {
    private struct State: Codable {
        var version = 1
        var folderIDs: [String: String] = [:]
        var cleanupRecords: [DriveTransferRecord] = []
    }

    private let fileURL: URL
    private var state: State

    public init(applicationSupportDirectory: URL? = nil) throws {
        let base: URL
        if let applicationSupportDirectory {
            base = applicationSupportDirectory
        } else {
            base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        let directory = base.appendingPathComponent("FileMailer", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        fileURL = directory.appendingPathComponent("DriveTransfers.json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            state = try JSONDecoder().decode(State.self, from: data)
        } else {
            state = State()
        }
    }

    public func folderID(for accountID: GmailAccountID) -> String? {
        state.folderIDs[accountID.rawValue]
    }

    public func setFolderID(_ folderID: String, for accountID: GmailAccountID) throws {
        state.folderIDs[accountID.rawValue] = folderID
        try persist()
    }

    public func removeFolderID(for accountID: GmailAccountID) throws {
        state.folderIDs.removeValue(forKey: accountID.rawValue)
        try persist()
    }

    public func removeAllMetadata(for accountID: GmailAccountID) throws {
        state.folderIDs.removeValue(forKey: accountID.rawValue)
        state.cleanupRecords.removeAll { $0.accountID == accountID }
        try persist()
    }

    public func schedule(_ record: DriveTransferRecord) throws {
        state.cleanupRecords.removeAll { $0.fileID == record.fileID }
        state.cleanupRecords.append(record)
        try persist()
    }

    public func dueRecords(now: Date = Date()) -> [DriveTransferRecord] {
        state.cleanupRecords
            .filter { $0.dueAt <= now }
            .sorted { $0.dueAt < $1.dueAt }
    }

    public func pendingRecords() -> [DriveTransferRecord] {
        state.cleanupRecords.sorted { $0.dueAt < $1.dueAt }
    }

    public func remove(recordID: UUID) throws {
        state.cleanupRecords.removeAll { $0.id == recordID }
        try persist()
    }

    public func markFailure(recordID: UUID, description: String, at date: Date = Date()) throws {
        guard let index = state.cleanupRecords.firstIndex(where: { $0.id == recordID }) else {
            return
        }
        state.cleanupRecords[index].lastFailureDescription = description
        state.cleanupRecords[index].lastAttemptAt = date
        try persist()
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}

public actor GoogleDriveClient {
    private struct DriveFileResponse: Decodable {
        let id: String
        let name: String?
        let mimeType: String?
        let trashed: Bool?
        let webViewLink: String?
    }

    private struct PermissionResponse: Decodable {
        let id: String
    }

    private struct GoogleErrorEnvelope: Decodable {
        struct Details: Decodable {
            let code: Int?
            let status: String?
            let message: String?
        }

        let error: Details
    }

    private let session: URLSession
    private let apiBase: URL
    private let uploadBase: URL

    public init(
        session: URLSession = .shared,
        apiBase: URL = URL(string: "https://www.googleapis.com/drive/v3")!,
        uploadBase: URL = URL(string: "https://www.googleapis.com/upload/drive/v3")!
    ) {
        self.session = session
        self.apiBase = apiBase
        self.uploadBase = uploadBase
    }

    public func validateFolder(id: String, accessToken: String) async throws {
        var components = URLComponents(
            url: apiBase.appendingPathComponent("files/\(id)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "id,mimeType,trashed")
        ]
        let response: DriveFileResponse = try await request(
            url: components.url!,
            method: "GET",
            accessToken: accessToken
        )
        guard response.mimeType == "application/vnd.google-apps.folder", response.trashed != true else {
            throw GoogleDriveError.fileNotFound
        }
    }

    public func createFolder(name: String, accessToken: String) async throws -> String {
        let metadata: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
            "appProperties": ["filemailer": "folder-v1"]
        ]
        var components = URLComponents(
            url: apiBase.appendingPathComponent("files"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "fields", value: "id,name,mimeType")]
        let response: DriveFileResponse = try await request(
            url: components.url!,
            method: "POST",
            accessToken: accessToken,
            jsonBody: metadata
        )
        return response.id
    }

    public func uploadReference(
        fileURL: URL,
        name: String,
        mimeType: String,
        parentID: String,
        accountID: GmailAccountID,
        accessToken: String
    ) async throws -> DriveFileReference {
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw GoogleDriveError.fileAccessLost
        }
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values.fileSize ?? 0)
        let metadata: [String: Any] = [
            "name": name,
            "parents": [parentID],
            "appProperties": ["filemailer": "upload-v1"]
        ]
        var components = URLComponents(
            url: uploadBase.appendingPathComponent("files"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "uploadType", value: "resumable"),
            URLQueryItem(name: "fields", value: "id,name,webViewLink")
        ]
        var start = URLRequest(url: components.url!)
        start.httpMethod = "POST"
        start.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        start.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        start.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        start.setValue(String(byteCount), forHTTPHeaderField: "X-Upload-Content-Length")
        start.timeoutInterval = 60
        start.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        let (startData, startResponse) = try await networkData(for: start)
        guard (200..<300).contains(startResponse.statusCode) else {
            throw Self.map(status: startResponse.statusCode, data: startData)
        }
        guard let location = startResponse.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location)
        else {
            throw GoogleDriveError.malformedResponse
        }

        var upload = URLRequest(url: uploadURL)
        upload.httpMethod = "PUT"
        upload.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        upload.setValue(String(byteCount), forHTTPHeaderField: "Content-Length")
        upload.timeoutInterval = 600
        do {
            let (data, response) = try await session.upload(for: upload, fromFile: fileURL)
            guard let http = response as? HTTPURLResponse else {
                throw GoogleDriveError.malformedResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw Self.map(status: http.statusCode, data: data)
            }
            let decoded = try JSONDecoder().decode(DriveFileResponse.self, from: data)
            guard let webViewURL = URL(
                string: decoded.webViewLink ?? "https://drive.google.com/file/d/\(decoded.id)/view"
            ) else {
                throw GoogleDriveError.malformedResponse
            }
            return DriveFileReference(
                id: decoded.id,
                webViewURL: webViewURL,
                accountID: accountID
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GoogleDriveError {
            throw error
        } catch let error as URLError {
            throw Self.map(error: error)
        }
    }

    public func grantUserReaderAccess(
        fileID: String,
        recipient: EmailAddress,
        expiresAt: Date?,
        accessToken: String
    ) async throws -> String {
        let body = Self.userReaderPermissionBody(
            recipient: recipient,
            expiresAt: expiresAt
        )
        var components = URLComponents(
            url: apiBase.appendingPathComponent("files/\(fileID)/permissions"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "id"),
            URLQueryItem(name: "sendNotificationEmail", value: "false")
        ]
        let response: PermissionResponse = try await request(
            url: components.url!,
            method: "POST",
            accessToken: accessToken,
            jsonBody: body
        )
        return response.id
    }

    static func userReaderPermissionBody(
        recipient: EmailAddress,
        expiresAt: Date?
    ) -> [String: Any] {
        var body: [String: Any] = [
            "emailAddress": recipient.address,
            "type": "user",
            "role": "reader"
        ]
        if let expiresAt {
            body["expirationTime"] = rfc3339(expiresAt)
        }
        return body
    }

    public func removePermission(
        fileID: String,
        permissionID: String,
        accessToken: String
    ) async throws {
        _ = try await requestWithoutResponse(
            url: apiBase.appendingPathComponent("files/\(fileID)/permissions/\(permissionID)"),
            method: "DELETE",
            accessToken: accessToken
        )
    }

    public func trash(fileID: String, accessToken: String) async throws {
        _ = try await requestWithoutResponse(
            url: apiBase.appendingPathComponent("files/\(fileID)"),
            method: "PATCH",
            accessToken: accessToken,
            jsonBody: ["trashed": true]
        )
    }

    public func delete(fileID: String, accessToken: String) async throws {
        _ = try await requestWithoutResponse(
            url: apiBase.appendingPathComponent("files/\(fileID)"),
            method: "DELETE",
            accessToken: accessToken
        )
    }

    private func request<Response: Decodable>(
        url: URL,
        method: String,
        accessToken: String,
        jsonBody: [String: Any]? = nil
    ) async throws -> Response {
        let data = try await requestWithoutResponse(
            url: url,
            method: method,
            accessToken: accessToken,
            jsonBody: jsonBody
        )
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GoogleDriveError.malformedResponse
        }
    }

    private func requestWithoutResponse(
        url: URL,
        method: String,
        accessToken: String,
        jsonBody: [String: Any]? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let jsonBody {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        let (data, response) = try await networkData(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.map(status: response.statusCode, data: data)
        }
        return data
    }

    private func networkData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GoogleDriveError.malformedResponse
            }
            return (data, http)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GoogleDriveError {
            throw error
        } catch let error as URLError {
            throw Self.map(error: error)
        }
    }

    private static func map(status: Int, data: Data) -> GoogleDriveError {
        let googleStatus = (try? JSONDecoder().decode(GoogleErrorEnvelope.self, from: data))?
            .error.status?.lowercased() ?? ""
        switch status {
        case 401:
            return .authorizationRequired
        case 403 where googleStatus.contains("permission") || googleStatus.contains("policy"):
            return .administratorPolicy
        case 403:
            return .sharingNotAllowed
        case 404:
            return .fileNotFound
        case 429:
            return .quota
        default:
            return .server(status: status)
        }
    }

    private static func map(error: URLError) -> GoogleDriveError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .timedOut:
            return .networkUnavailable
        default:
            return .networkUnavailable
        }
    }

    private static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public actor GoogleDriveTransferCoordinator {
    private let client: GoogleDriveClient
    private let tokenProvider: any TokenProviding
    private let store: DriveTransferStore

    public init(
        client: GoogleDriveClient = GoogleDriveClient(),
        tokenProvider: any TokenProviding,
        store: DriveTransferStore
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.store = store
    }

    public func prepare(
        attachment: ComposeAttachment,
        accountID: GmailAccountID
    ) async throws -> DriveFileReference {
        guard attachment.contentType != "inode/directory" else {
            throw GoogleDriveError.fileAccessLost
        }
        let accessToken = try await tokenProvider.validAccessToken(for: accountID)
        let folderID = try await fileMailerFolderID(
            for: accountID,
            accessToken: accessToken
        )
        return try await client.uploadReference(
            fileURL: attachment.url,
            name: attachment.displayName,
            mimeType: attachment.contentType,
            parentID: folderID,
            accountID: accountID,
            accessToken: accessToken
        )
    }

    public func grantRecipientReaderAccess(
        to file: DriveFileReference,
        recipients: [EmailAddress],
        expiresAt: Date?
    ) async throws {
        let uniqueRecipients = Self.uniqueRecipients(recipients)
        guard !uniqueRecipients.isEmpty else { throw GoogleDriveError.missingRecipients }
        let accessToken = try await tokenProvider.validAccessToken(for: file.accountID)
        var permissionIDs: [String] = []
        do {
            for recipient in uniqueRecipients {
                let permissionID = try await client.grantUserReaderAccess(
                    fileID: file.id,
                    recipient: recipient,
                    expiresAt: expiresAt,
                    accessToken: accessToken
                )
                permissionIDs.append(permissionID)
            }
        } catch {
            for permissionID in permissionIDs.reversed() {
                try? await client.removePermission(
                    fileID: file.id,
                    permissionID: permissionID,
                    accessToken: accessToken
                )
            }
            throw error
        }
    }

    public func scheduleCleanup(
        for file: DriveFileReference,
        displayName: String,
        action: DriveCleanupAction,
        dueAt: Date?
    ) async throws {
        guard action != .keep, let dueAt else { return }
        try await store.schedule(
            DriveTransferRecord(
                accountID: file.accountID,
                fileID: file.id,
                displayName: displayName,
                action: action,
                dueAt: dueAt
            )
        )
    }

    public func discardPreparedFile(_ file: DriveFileReference) async throws {
        let accessToken = try await tokenProvider.validAccessToken(for: file.accountID)
        try await client.trash(fileID: file.id, accessToken: accessToken)
    }

    public func cleanDueTransfers(now: Date = Date()) async -> [GoogleDriveCleanupOutcome] {
        let records = await store.dueRecords(now: now)
        var outcomes: [GoogleDriveCleanupOutcome] = []
        for record in records {
            do {
                let accessToken = try await tokenProvider.validAccessToken(for: record.accountID)
                switch record.action {
                case .keep:
                    break
                case .trash:
                    try await client.trash(fileID: record.fileID, accessToken: accessToken)
                case .delete:
                    try await client.delete(fileID: record.fileID, accessToken: accessToken)
                }
                try await store.remove(recordID: record.id)
                outcomes.append(.removed(record))
            } catch {
                let description = (error as? LocalizedError)?.errorDescription
                    ?? "La suppression Drive a échoué."
                try? await store.markFailure(recordID: record.id, description: description)
                outcomes.append(.failed(record, description))
            }
        }
        return outcomes
    }

    public func pendingCleanups() async -> [DriveTransferRecord] {
        await store.pendingRecords()
    }

    private func fileMailerFolderID(
        for accountID: GmailAccountID,
        accessToken: String
    ) async throws -> String {
        if let existing = await store.folderID(for: accountID) {
            do {
                try await client.validateFolder(id: existing, accessToken: accessToken)
                return existing
            } catch GoogleDriveError.fileNotFound {
                try await store.removeFolderID(for: accountID)
            }
        }
        let created = try await client.createFolder(name: "FileMailer", accessToken: accessToken)
        try await store.setFolderID(created, for: accountID)
        return created
    }

    private static func uniqueRecipients(_ recipients: [EmailAddress]) -> [EmailAddress] {
        var addresses = Set<String>()
        return recipients.filter { addresses.insert($0.normalized).inserted }
    }
}

public enum GoogleDriveCleanupOutcome: Sendable {
    case removed(DriveTransferRecord)
    case failed(DriveTransferRecord, String)
}
