import FileMailerDomain
import Foundation

/// Only menu metadata and bounded action requests belong in this shared container.
/// Attachments, message bodies and account credentials stay in the main app.
public struct SharedFinderStateStore: Sendable {
    private let directory: URL

    public init(containerURL: URL) {
        directory = containerURL.appendingPathComponent("FinderState", isDirectory: true)
    }

    public static func configured(bundle: Bundle = .main) -> Self? {
        guard let identifier = bundle.object(forInfoDictionaryKey: "FileMailerApplicationGroupIdentifier") as? String,
              !identifier.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { return nil }
        return Self(containerURL: container)
    }

    public func saveSnapshot(_ snapshot: FinderMenuSnapshot) throws {
        guard snapshot.schemaVersion == 1, snapshot.recipients.count <= 50,
              (1...10).contains(snapshot.visibleRecipientCount) else {
            throw IPCError.unsupportedSchema
        }
        try save(snapshot, to: directory.appendingPathComponent("snapshot.json"), limit: .snapshot)
    }

    public func loadSnapshot() throws -> FinderMenuSnapshot? {
        let url = directory.appendingPathComponent("snapshot.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let snapshot: FinderMenuSnapshot = try load(from: url, limit: .snapshot)
        guard snapshot.schemaVersion == 1, snapshot.recipients.count <= 50,
              (1...10).contains(snapshot.visibleRecipientCount) else {
            throw IPCError.unsupportedSchema
        }
        return snapshot
    }

    public func saveAction(_ action: IPCActionEnvelope, now: Date = Date()) throws {
        try ComposeActionValidator().validate(action.request, now: now)
        let allowedCommands: Set<String> = ["openApp", "editRecipients"]
        guard action.command == nil || allowedCommands.contains(action.command!) else {
            throw IPCError.invalidChunk
        }
        let actions = directory.appendingPathComponent("Actions", isDirectory: true)
        try FileManager.default.createDirectory(at: actions, withIntermediateDirectories: true)
        // Interrupted launches must not leave an unbounded queue behind.
        let files = try FileManager.default.contentsOfDirectory(
            at: actions, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )
        var remainingCount = files.count
        for file in files where file.pathExtension == "json" {
            let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if modified.map({ now.timeIntervalSince($0) > 60 }) ?? true {
                try FileManager.default.removeItem(at: file)
                remainingCount -= 1
            }
        }
        guard remainingCount < 100 else { throw IPCError.rateLimited }
        try save(action, to: actionURL(action.request.requestID), limit: .action)
    }

    public func takeAction(id: UUID, now: Date = Date()) throws -> IPCActionEnvelope {
        let url = actionURL(id)
        let action: IPCActionEnvelope = try load(from: url, limit: .action)
        guard action.request.requestID == id else { throw IPCError.invalidChunk }
        try ComposeActionValidator().validate(action.request, now: now)
        if let command = action.command, !["openApp", "editRecipients"].contains(command) {
            throw IPCError.invalidChunk
        }
        try FileManager.default.removeItem(at: url)
        return action
    }

    private func actionURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("Actions", isDirectory: true)
            .appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func save<T: Encodable>(_ value: T, to url: URL, limit: IPCPayloadLimit) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(value)
        guard data.count <= limit.rawValue else { throw IPCError.payloadTooLarge }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func load<T: Decodable>(from url: URL, limit: IPCPayloadLimit) throws -> T {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= limit.rawValue else { throw IPCError.payloadTooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= limit.rawValue else { throw IPCError.payloadTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(T.self, from: data)
    }
}
