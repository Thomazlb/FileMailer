import FileMailerCore
import Foundation

@MainActor
final class AppIPCService {
    private unowned let model: AppModel
    private let notifications = DistributedNotificationCenter.default()
    private let names = IPCNotificationNames(baseBundleID: AppConfiguration.baseBundleID)
    private let store = SharedFinderStateStore.configured()
    private let actionURLCodec = IPCActionURLCodec()
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
        do {
            guard let store else { throw IPCError.invalidChunk }
            try store.saveSnapshot(snapshot)
            notifications.postNotificationName(
                names.snapshotChanged, object: nil, userInfo: nil, deliverImmediately: true
            )
        } catch {
            model.addDiagnostic(category: "ipc", message: error.localizedDescription)
            return
        }
        model.lastSnapshotDate = snapshot.generatedAt
    }

    func handleActionURL(_ url: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let envelope: IPCActionEnvelope
                if let id = actionURLCodec.referenceID(from: url), let store {
                    envelope = try store.takeAction(id: id)
                } else {
                    // Keep existing Developer ID installations compatible during the transition.
                    envelope = try actionURLCodec.decode(url)
                }
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

    private func process(
        _ request: ComposeActionRequest,
        command: String?
    ) async throws {
        try validator.validate(request, now: Date())
        try await deduplicator.accept(request.requestID, now: Date())
        guard command == nil || command == "editRecipients" || command == "openApp" else {
            throw IPCError.invalidChunk
        }
        defer { publishAcknowledgement(for: request.requestID) }
        if command == "editRecipients" {
            model.windows?.showSettings(section: .recipients)
        } else if command == "openApp" {
            model.windows?.showSettings()
        } else {
            try model.openFinderCompose(paths: request.paths, recipientID: request.recipientID)
        }
    }

    private func publishAcknowledgement(for requestID: UUID) {
        notifications.postNotificationName(
            names.actionAcknowledgement,
            object: requestID.uuidString,
            userInfo: nil,
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
