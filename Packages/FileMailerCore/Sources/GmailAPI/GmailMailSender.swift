import FileMailerDomain
import Foundation

public enum GmailSendError: Error, LocalizedError, Sendable {
    case authenticationExpired
    case accountRevoked
    case administratorPolicy
    case quota
    case messageTooLarge
    case invalidAddress
    case fileAccessLost
    case networkUnavailable
    case ambiguousTimeout
    case server(status: Int)
    case malformedResponse
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .authenticationExpired: "La session Gmail a expiré. Reconnectez le compte."
        case .accountRevoked: "L’accès Gmail a été révoqué."
        case .administratorPolicy: "L’administrateur Google Workspace bloque cette application."
        case .quota: "Le quota Gmail est temporairement dépassé."
        case .messageTooLarge: "Le message dépasse la taille autorisée par Gmail."
        case .invalidAddress: "Google a refusé une adresse de destinataire."
        case .fileAccessLost: "Une pièce jointe n’est plus accessible."
        case .networkUnavailable: "Le réseau est indisponible."
        case .ambiguousTimeout:
            "État d’envoi incertain. Vérifiez le dossier Envoyés dans Gmail avant de réessayer."
        case let .server(status): "Le serveur Gmail a répondu avec l’erreur \(status)."
        case .malformedResponse: "La réponse Gmail est illisible."
        case .cancelled: "L’envoi a été annulé."
        }
    }
}

public actor GmailMailSender: MailSending {
    public static let simpleUploadLimit: Int64 = 5 * 1_024 * 1_024

    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(
            string: "https://gmail.googleapis.com/upload/gmail/v1/users/me/messages/send"
        )!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func send(
        messageFile: URL,
        size: Int64,
        accessToken: String
    ) async throws -> MailSendReceipt {
        guard FileManager.default.isReadableFile(atPath: messageFile.path) else {
            throw GmailSendError.fileAccessLost
        }
        do {
            if size <= Self.simpleUploadLimit {
                return try await simpleUpload(
                    messageFile: messageFile,
                    accessToken: accessToken
                )
            }
            return try await resumableUpload(
                messageFile: messageFile,
                size: size,
                accessToken: accessToken
            )
        } catch is CancellationError {
            throw GmailSendError.cancelled
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw GmailSendError.ambiguousTimeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed:
                throw GmailSendError.networkUnavailable
            case .cancelled:
                throw GmailSendError.cancelled
            default:
                throw GmailSendError.networkUnavailable
            }
        }
    }

    private func simpleUpload(
        messageFile: URL,
        accessToken: String
    ) async throws -> MailSendReceipt {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "uploadType", value: "media")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("message/rfc822", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        let (data, response) = try await session.upload(for: request, fromFile: messageFile)
        return try parse(data: data, response: response)
    }

    private func resumableUpload(
        messageFile: URL,
        size: Int64,
        accessToken: String
    ) async throws -> MailSendReceipt {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "uploadType", value: "resumable")]
        var startRequest = URLRequest(url: components.url!)
        startRequest.httpMethod = "POST"
        startRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        startRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        startRequest.setValue("message/rfc822", forHTTPHeaderField: "X-Upload-Content-Type")
        startRequest.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
        startRequest.httpBody = Data("{}".utf8)
        startRequest.timeoutInterval = 30

        let (startData, startResponse) = try await session.data(for: startRequest)
        guard let http = startResponse as? HTTPURLResponse else {
            throw GmailSendError.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            _ = try parse(data: startData, response: startResponse)
            throw GmailSendError.server(status: http.statusCode)
        }
        guard let location = http.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location)
        else {
            throw GmailSendError.malformedResponse
        }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("message/rfc822", forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue(String(size), forHTTPHeaderField: "Content-Length")
        uploadRequest.timeoutInterval = 300
        let (data, response) = try await session.upload(for: uploadRequest, fromFile: messageFile)
        return try parse(data: data, response: response)
    }

    private func parse(data: Data, response: URLResponse) throws -> MailSendReceipt {
        guard let http = response as? HTTPURLResponse else {
            throw GmailSendError.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.map(status: http.statusCode, data: data)
        }
        struct Response: Decodable {
            let id: String
            let threadId: String?
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw GmailSendError.malformedResponse
        }
        return MailSendReceipt(messageID: decoded.id, threadID: decoded.threadId)
    }

    private static func map(status: Int, data: Data) -> GmailSendError {
        let sanitized = String(data: data.prefix(16_384), encoding: .utf8)?.lowercased() ?? ""
        switch status {
        case 400 where sanitized.contains("too large") || sanitized.contains("limit"):
            return .messageTooLarge
        case 400:
            return .invalidAddress
        case 401:
            return sanitized.contains("invalid_grant") ? .accountRevoked : .authenticationExpired
        case 403:
            if sanitized.contains("policy") || sanitized.contains("admin") {
                return .administratorPolicy
            }
            return .quota
        case 413:
            return .messageTooLarge
        case 429:
            return .quota
        default:
            return .server(status: status)
        }
    }
}

public actor GmailUploadCoordinator {
    private let sender: any MailSending
    private let tokenProvider: any TokenProviding

    public init(sender: any MailSending, tokenProvider: any TokenProviding) {
        self.sender = sender
        self.tokenProvider = tokenProvider
    }

    public func send(
        messageFile: URL,
        size: Int64,
        accountID: GmailAccountID
    ) async throws -> MailSendReceipt {
        let firstToken = try await tokenProvider.validAccessToken(for: accountID)
        do {
            return try await sender.send(
                messageFile: messageFile,
                size: size,
                accessToken: firstToken
            )
        } catch GmailSendError.authenticationExpired {
            let refreshedToken = try await tokenProvider.validAccessToken(for: accountID)
            return try await sender.send(
                messageFile: messageFile,
                size: size,
                accessToken: refreshedToken
            )
        }
    }
}
