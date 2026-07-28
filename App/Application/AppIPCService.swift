import FileMailerCore
import Foundation

@MainActor
final class AppIPCService {
    private unowned let model: AppModel
    private let notifications = DistributedNotificationCenter.default()
    private let names = IPCNotificationNames(baseBundleID: AppConfiguration.baseBundleID)
    private let codec = IPCCodec()
    private let actionURLCodec = IPCActionURLCodec()
    private let reassembler = IPCChunkReassembler()
    private let deduplicator = RequestDeduplicator()
    private let validator = ComposeActionValidator()
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var localObservers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var heartbeatTimer: Timer?

    init(model: AppModel) {
        self.model = model
        observe()
        publishHeartbeat()
        publishSnapshot()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.publishHeartbeat() }
        }
    }

    deinit {
        heartbeatTimer?.invalidate()
        observers.forEach(notifications.removeObserver)
        localObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func publishSnapshot() {
        let snapshot = model.finderSnapshot()
        guard let chunks = try? codec.encode(snapshot, limit: .snapshot) else {
            model.addDiagnostic(category: "ipc", message: "Snapshot trop volumineux.")
            return
        }
        for chunk in chunks {
            notifications.postNotificationName(
                names.snapshotChunk,
                object: nil,
                userInfo: chunk.notificationUserInfo(),
                deliverImmediately: true
            )
        }
        model.lastSnapshotDate = snapshot.generatedAt
    }

    func handleActionURL(_ url: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let envelope = try actionURLCodec.decode(url)
                try await process(
                    envelope.request,
                    command: envelope.command
                )
            } catch {
                model.addDiagnostic(
                    category: "ipc",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func observe() {
        observers.append(
            notifications.addObserver(
                forName: names.extensionHeartbeat,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.model.lastExtensionHeartbeat = Date() }
            }
        )
        observers.append(
            notifications.addObserver(
                forName: names.snapshotRequest,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.publishSnapshot() }
            }
        )
        observers.append(
            notifications.addObserver(
                forName: names.actionChunk,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let chunk = IPCChunk(notificationUserInfo: notification.userInfo)
                else {
                    return
                }
                let command = notification.userInfo?["command"] as? String
                Task { @MainActor in await self.ingest(chunk, command: command) }
            }
        )
        localObservers.append(
            NotificationCenter.default.addObserver(
                forName: .fileMailerSnapshotNeedsRefresh,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.publishSnapshot() }
            }
        )
    }

    private func ingest(_ chunk: IPCChunk, command: String?) async {
        do {
            guard let chunks = try await reassembler.ingest(chunk) else { return }
            let request = try codec.decode(
                ComposeActionRequest.self,
                from: chunks,
                limit: .action
            )
            try await process(request, command: command)
        } catch {
            model.addDiagnostic(category: "ipc", message: error.localizedDescription)
        }
    }

    private func process(
        _ request: ComposeActionRequest,
        command: String?
    ) async throws {
        try validator.validate(request, now: Date())
        try await deduplicator.accept(request.requestID, now: Date())
        if command == "editRecipients" {
            model.windows?.showSettings(section: .recipients)
        } else if command == "openApp" {
            model.windows?.showSettings()
        } else {
            model.openCompose(paths: request.paths, recipientID: request.recipientID)
        }
        publishAcknowledgement(for: request.requestID)
    }

    private func publishAcknowledgement(for requestID: UUID) {
        notifications.postNotificationName(
            names.actionAcknowledgement,
            object: nil,
            userInfo: ["requestID": requestID.uuidString],
            deliverImmediately: true
        )
    }

    private func publishHeartbeat() {
        notifications.postNotificationName(
            names.appHeartbeat,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
