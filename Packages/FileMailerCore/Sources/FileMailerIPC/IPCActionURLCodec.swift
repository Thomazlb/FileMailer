import FileMailerDomain
import Foundation

public struct IPCActionEnvelope: Codable, Sendable, Equatable {
    public let request: ComposeActionRequest
    public let command: String?

    public init(request: ComposeActionRequest, command: String?) {
        self.request = request
        self.command = command
    }
}

public struct IPCActionURLCodec: Sendable {
    public static let scheme = "filemailer"
    public static let host = "action"

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    public func encode(
        request: ComposeActionRequest,
        command: String?
    ) throws -> URL {
        let envelope = IPCActionEnvelope(request: request, command: command)
        let data = try encoder.encode(envelope)
        guard data.count <= IPCPayloadLimit.action.rawValue else {
            throw IPCError.payloadTooLarge
        }

        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = [
            URLQueryItem(name: "payload", value: Self.base64URLEncoded(data))
        ]
        guard let url = components.url else {
            throw IPCError.invalidChunk
        }
        return url
    }

    public func decode(_ url: URL) throws -> IPCActionEnvelope {
        guard url.scheme?.lowercased() == Self.scheme,
              url.host?.lowercased() == Self.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let payload = components.queryItems?.first(where: { $0.name == "payload" })?.value,
              let data = Self.base64URLDecoded(payload),
              data.count <= IPCPayloadLimit.action.rawValue
        else {
            throw IPCError.invalidChunk
        }
        return try decoder.decode(IPCActionEnvelope.self, from: data)
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecoded(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}
