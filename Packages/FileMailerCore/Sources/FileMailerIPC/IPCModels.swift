import CryptoKit
import FileMailerDomain
import Foundation

public struct IPCChunk: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let messageID: UUID
    public let index: Int
    public let count: Int
    public let sha256: String
    public let payloadBase64: String

    public init(
        schemaVersion: Int = 1,
        messageID: UUID,
        index: Int,
        count: Int,
        sha256: String,
        payloadBase64: String
    ) {
        self.schemaVersion = schemaVersion
        self.messageID = messageID
        self.index = index
        self.count = count
        self.sha256 = sha256
        self.payloadBase64 = payloadBase64
    }
}

public enum IPCError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedSchema
    case invalidChunk
    case tooManyChunks
    case payloadTooLarge
    case checksumMismatch
    case incompleteMessage
    case expiredAction
    case duplicateRequest
    case invalidPath
    case rateLimited

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema: FileMailerLocalization.current.string("IPC version not supported.")
        case .invalidChunk: FileMailerLocalization.current.string("Invalid IPC fragment.")
        case .tooManyChunks: FileMailerLocalization.current.string("The IPC message contains too many fragments.")
        case .payloadTooLarge: FileMailerLocalization.current.string("The IPC message exceeds the allowed size.")
        case .checksumMismatch: FileMailerLocalization.current.string("The IPC integrity check failed.")
        case .incompleteMessage: FileMailerLocalization.current.string("The IPC message is incomplete.")
        case .expiredAction: FileMailerLocalization.current.string("The Finder request has expired.")
        case .duplicateRequest: FileMailerLocalization.current.string("The Finder request has already been processed.")
        case .invalidPath: FileMailerLocalization.current.string("A Finder path is invalid.")
        case .rateLimited: FileMailerLocalization.current.string("Too many Finder requests close together.")
        }
    }
}

public enum IPCPayloadLimit: Int, Sendable {
    case snapshot = 262_144
    case action = 131_072
}

public struct IPCCodec: Sendable {
    public static let schemaVersion = 1
    public static let maximumChunkCount = 64
    public static let maximumSerializedChunkBytes = 65_536
    private static let rawChunkBytes = 44 * 1024

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    public func encode<T: Encodable & Sendable>(
        _ value: T,
        limit: IPCPayloadLimit,
        messageID: UUID = UUID()
    ) throws -> [IPCChunk] {
        let data = try encoder.encode(value)
        guard data.count <= limit.rawValue else { throw IPCError.payloadTooLarge }
        let checksum = Self.hexDigest(data)
        let count = max(1, Int(ceil(Double(data.count) / Double(Self.rawChunkBytes))))
        guard count <= Self.maximumChunkCount else { throw IPCError.tooManyChunks }

        return try (0..<count).map { index in
            let start = index * Self.rawChunkBytes
            let end = min(start + Self.rawChunkBytes, data.count)
            let payload = data.subdata(in: start..<end).base64EncodedString()
            let chunk = IPCChunk(
                messageID: messageID,
                index: index,
                count: count,
                sha256: checksum,
                payloadBase64: payload
            )
            guard try encoder.encode(chunk).count <= Self.maximumSerializedChunkBytes else {
                throw IPCError.payloadTooLarge
            }
            return chunk
        }
    }

    public func decode<T: Decodable & Sendable>(
        _ type: T.Type,
        from chunks: [IPCChunk],
        limit: IPCPayloadLimit
    ) throws -> T {
        guard let first = chunks.first else { throw IPCError.incompleteMessage }
        guard first.schemaVersion == Self.schemaVersion else { throw IPCError.unsupportedSchema }
        guard first.count > 0, first.count <= Self.maximumChunkCount else {
            throw IPCError.tooManyChunks
        }
        guard chunks.count == first.count else { throw IPCError.incompleteMessage }

        let sorted = chunks.sorted { $0.index < $1.index }
        var data = Data()
        for (expectedIndex, chunk) in sorted.enumerated() {
            guard chunk.messageID == first.messageID,
                  chunk.schemaVersion == first.schemaVersion,
                  chunk.count == first.count,
                  chunk.sha256 == first.sha256,
                  chunk.index == expectedIndex,
                  let part = Data(base64Encoded: chunk.payloadBase64)
            else {
                throw IPCError.invalidChunk
            }
            guard data.count + part.count <= limit.rawValue else { throw IPCError.payloadTooLarge }
            data.append(part)
        }

        guard Self.hexDigest(data) == first.sha256 else { throw IPCError.checksumMismatch }
        return try decoder.decode(type, from: data)
    }

    private static func hexDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct IPCNotificationNames: Sendable {
    public let appHeartbeat: Notification.Name
    public let extensionHeartbeat: Notification.Name
    public let snapshotRequest: Notification.Name
    public let snapshotChanged: Notification.Name
    public let snapshotChunk: Notification.Name
    public let actionChunk: Notification.Name
    public let actionAcknowledgement: Notification.Name

    public init(baseBundleID: String) {
        appHeartbeat = Notification.Name("\(baseBundleID).ipc.app-heartbeat")
        extensionHeartbeat = Notification.Name("\(baseBundleID).ipc.extension-heartbeat")
        snapshotRequest = Notification.Name("\(baseBundleID).ipc.snapshot-request")
        snapshotChanged = Notification.Name("\(baseBundleID).ipc.snapshot-changed")
        snapshotChunk = Notification.Name("\(baseBundleID).ipc.snapshot-chunk")
        actionChunk = Notification.Name("\(baseBundleID).ipc.action-chunk")
        actionAcknowledgement = Notification.Name("\(baseBundleID).ipc.action-acknowledgement")
    }
}
