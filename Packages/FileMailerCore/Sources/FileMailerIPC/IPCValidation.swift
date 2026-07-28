import FileMailerDomain
import Foundation

public struct ComposeActionValidator: Sendable {
    public static let maximumPathCount = 50
    public static let maximumPathBytes = 4_096
    public static let maximumAge: TimeInterval = 30

    public init() {}

    public func validate(_ request: ComposeActionRequest, now: Date) throws {
        guard request.schemaVersion == IPCCodec.schemaVersion else {
            throw IPCError.unsupportedSchema
        }
        guard abs(now.timeIntervalSince(request.createdAt)) <= Self.maximumAge else {
            throw IPCError.expiredAction
        }
        guard !request.paths.isEmpty, request.paths.count <= Self.maximumPathCount else {
            throw IPCError.invalidPath
        }
        for path in request.paths {
            guard !path.isEmpty,
                  path.utf8.count <= Self.maximumPathBytes,
                  !path.unicodeScalars.contains(where: {
                      $0.value == 0 || ($0.value < 32 && $0.value != 9)
                  })
            else {
                throw IPCError.invalidPath
            }
        }
    }
}

public actor RequestDeduplicator {
    private var seen: [UUID: Date] = [:]
    private var recentActionDates: [Date] = []
    private let retention: TimeInterval
    private let maximumActionsPerWindow: Int
    private let rateWindow: TimeInterval

    public init(
        retention: TimeInterval = 300,
        maximumActionsPerWindow: Int = 10,
        rateWindow: TimeInterval = 10
    ) {
        self.retention = retention
        self.maximumActionsPerWindow = maximumActionsPerWindow
        self.rateWindow = rateWindow
    }

    public func accept(_ requestID: UUID, now: Date) throws {
        seen = seen.filter { now.timeIntervalSince($0.value) < retention }
        recentActionDates = recentActionDates.filter { now.timeIntervalSince($0) < rateWindow }
        guard seen[requestID] == nil else { throw IPCError.duplicateRequest }
        guard recentActionDates.count < maximumActionsPerWindow else { throw IPCError.rateLimited }
        seen[requestID] = now
        recentActionDates.append(now)
    }
}

public actor IPCChunkReassembler {
    private struct Pending: Sendable {
        var chunks: [Int: IPCChunk]
        let createdAt: Date
        let expectedCount: Int
    }

    private var messages: [UUID: Pending] = [:]
    private let maximumMessages: Int
    private let expiration: TimeInterval

    public init(maximumMessages: Int = 16, expiration: TimeInterval = 5) {
        self.maximumMessages = maximumMessages
        self.expiration = expiration
    }

    public func ingest(_ chunk: IPCChunk, now: Date = Date()) throws -> [IPCChunk]? {
        messages = messages.filter { now.timeIntervalSince($0.value.createdAt) < expiration }
        guard chunk.schemaVersion == IPCCodec.schemaVersion,
              chunk.count > 0,
              chunk.count <= IPCCodec.maximumChunkCount,
              chunk.index >= 0,
              chunk.index < chunk.count
        else {
            throw IPCError.invalidChunk
        }
        if messages[chunk.messageID] == nil {
            guard messages.count < maximumMessages else { throw IPCError.rateLimited }
            messages[chunk.messageID] = Pending(
                chunks: [:],
                createdAt: now,
                expectedCount: chunk.count
            )
        }
        guard var pending = messages[chunk.messageID],
              pending.expectedCount == chunk.count
        else {
            throw IPCError.invalidChunk
        }
        pending.chunks[chunk.index] = chunk
        messages[chunk.messageID] = pending
        guard pending.chunks.count == pending.expectedCount else { return nil }
        messages.removeValue(forKey: chunk.messageID)
        return pending.chunks.values.sorted { $0.index < $1.index }
    }
}

public extension IPCChunk {
    func notificationUserInfo() -> [AnyHashable: Any] {
        [
            "schemaVersion": schemaVersion,
            "messageID": messageID.uuidString,
            "index": index,
            "count": count,
            "sha256": sha256,
            "payloadBase64": payloadBase64
        ]
    }

    init?(notificationUserInfo: [AnyHashable: Any]?) {
        guard let info = notificationUserInfo,
              let schemaVersion = info["schemaVersion"] as? Int,
              let messageIDString = info["messageID"] as? String,
              let messageID = UUID(uuidString: messageIDString),
              let index = info["index"] as? Int,
              let count = info["count"] as? Int,
              let sha256 = info["sha256"] as? String,
              let payloadBase64 = info["payloadBase64"] as? String
        else {
            return nil
        }
        self.init(
            schemaVersion: schemaVersion,
            messageID: messageID,
            index: index,
            count: count,
            sha256: sha256,
            payloadBase64: payloadBase64
        )
    }
}
