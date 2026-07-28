import AppKit
import FileMailerDomain
import FileMailerIPC
import FinderSync

final class FinderSync: FIFinderSync, @unchecked Sendable {
    private struct PendingFeedback {
        let requestID: UUID
        let startedAt: Date
    }

    private enum PendingAction {
        case recipient(RecipientID)
        case otherRecipient
        case editRecipients
        case openApp
    }

    private let controller = FIFinderSyncController.default()
    private let notifications = DistributedNotificationCenter.default()
    private let codec = IPCCodec()
    private let actionURLCodec = IPCActionURLCodec()
    private let baseBundleID: String
    private let names: IPCNotificationNames
    private let reassembler = IPCChunkReassembler()
    private var snapshot = FinderMenuSnapshot(recipients: [], visibleRecipientCount: 5)
    private var lastAppHeartbeat = Date.distantPast
    private var actions: [Int: PendingAction] = [:]
    private var nextTag = 1
    private var observers: [NSObjectProtocol] = []
    private var heartbeatTimer: Timer?
    private var pendingFeedback: PendingFeedback?

    override init() {
        let baseBundleID = Bundle.main.bundleIdentifier?
            .replacingOccurrences(of: ".FinderExtension", with: "")
            ?? "org.filemailer.FileMailer"
        self.baseBundleID = baseBundleID
        names = IPCNotificationNames(baseBundleID: baseBundleID)
        super.init()
        updateDirectoryURLs()
        observeVolumes()
        observeIPC()
        postExtensionHeartbeat()
        notifications.post(name: names.snapshotRequest, object: nil)
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: 2,
            repeats: true
        ) { [weak self] _ in
            self?.postExtensionHeartbeat()
        }
    }

    deinit {
        heartbeatTimer?.invalidate()
        observers.forEach(notifications.removeObserver)
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }
        actions.removeAll(keepingCapacity: true)
        nextTag = 1
        let root = NSMenu()
        let menuTitle = menuKind == .contextualMenuForContainer
            ? String(localized: "Envoyer ce dossier par e-mail")
            : String(localized: "Send by Email")
        let parent = NSMenuItem(
            title: menuTitle,
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu(title: menuTitle)
        if let pendingFeedback, Date().timeIntervalSince(pendingFeedback.startedAt) <= 20 {
            let status = NSMenuItem(
                title: String(localized: "Préparation avec Apple Intelligence…"),
                action: nil,
                keyEquivalent: ""
            )
            status.image = NSImage(
                systemSymbolName: "apple.intelligence",
                accessibilityDescription: String(localized: "Préparation du message")
            )
            status.isEnabled = false
            submenu.addItem(status)
            submenu.addItem(.separator())
        } else {
            pendingFeedback = nil
        }
        for recipient in snapshot.recipients.prefix(snapshot.visibleRecipientCount) {
            add(
                title: recipient.title,
                action: .recipient(recipient.recipientID),
                to: submenu
            )
        }
        add(
            title: String(localized: "Other Recipient…"),
            action: .otherRecipient,
            to: submenu
        )
        add(
            title: String(localized: "Edit Recipients…"),
            action: .editRecipients,
            to: submenu
        )
        add(
            title: String(localized: "Open FileMailer…"),
            action: .openApp,
            to: submenu
        )
        parent.submenu = submenu
        root.addItem(parent)
        return root
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let action = actions[sender.tag] else { return }
        sender.title = String(localized: "Préparation du message…")
        sender.image = NSImage(
            systemSymbolName: "apple.intelligence",
            accessibilityDescription: String(localized: "Préparation du message")
        )
        sender.isEnabled = false
        switch action {
        case .openApp:
            sendAction(recipientID: nil, auxiliaryCommand: "openApp")
        case .editRecipients:
            sendAction(recipientID: nil, auxiliaryCommand: "editRecipients")
        case .otherRecipient:
            sendAction(recipientID: nil, auxiliaryCommand: nil)
        case let .recipient(recipientID):
            sendAction(recipientID: recipientID, auxiliaryCommand: nil)
        }
    }

    private func sendAction(recipientID: RecipientID?, auxiliaryCommand: String?) {
        guard let selection = selection() else { return }
        let request = ComposeActionRequest(
            recipientID: recipientID,
            context: selection.context,
            paths: selection.paths
        )
        guard let actionURL = try? actionURLCodec.encode(
            request: request,
            command: auxiliaryCommand
        ) else {
            return
        }
        pendingFeedback = PendingFeedback(
            requestID: request.requestID,
            startedAt: Date()
        )

        if NSWorkspace.shared.open(actionURL) {
            return
        }

        guard let chunks = try? codec.encode(request, limit: .action) else {
            pendingFeedback = nil
            return
        }
        activateContainerApp { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.postAction(chunks, auxiliaryCommand: auxiliaryCommand)
            }
        }
    }

    private func postAction(_ chunks: [IPCChunk], auxiliaryCommand: String?) {
        for chunk in chunks {
            var info = chunk.notificationUserInfo()
            if let auxiliaryCommand { info["command"] = auxiliaryCommand }
            notifications.postNotificationName(
                names.actionChunk,
                object: nil,
                userInfo: info,
                deliverImmediately: true
            )
        }
    }

    private func selection() -> (context: FinderSelectionContext, paths: [String])? {
        let urls: [URL]
        let context: FinderSelectionContext
        if let selected = controller.selectedItemURLs(), !selected.isEmpty {
            urls = Array(selected.prefix(50))
            context = .selectedItems
        } else if let target = controller.targetedURL() {
            urls = [target]
            context = .currentContainer
        } else {
            return nil
        }
        let paths = urls.map(\.path).filter(Self.isValidPath)
        guard !paths.isEmpty else { return nil }
        return (context, paths)
    }

    private static func isValidPath(_ path: String) -> Bool {
        !path.isEmpty
            && path.utf8.count <= 4_096
            && !path.unicodeScalars.contains {
                $0.value == 0 || ($0.value < 32 && $0.value != 9)
            }
    }

    private func add(title: String, action: PendingAction, to menu: NSMenu) {
        let tag = nextTag
        nextTag += 1
        actions[tag] = action
        let item = NSMenuItem(
            title: title,
            action: #selector(performMenuAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = tag
        menu.addItem(item)
    }

    private func updateDirectoryURLs() {
        var urls = Set<URL>([URL(fileURLWithPath: "/", isDirectory: true)])
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []
        urls.formUnion(mounted)
        controller.directoryURLs = urls
    }

    private func observeVolumes() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didMountNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.updateDirectoryURLs() }
        )
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didUnmountNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.updateDirectoryURLs() }
        )
    }

    private func observeIPC() {
        observers.append(
            notifications.addObserver(
                forName: names.appHeartbeat,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.lastAppHeartbeat = Date() }
        )
        observers.append(
            notifications.addObserver(
                forName: names.snapshotChunk,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let chunk = IPCChunk(notificationUserInfo: notification.userInfo)
                else {
                    return
                }
                Task {
                    guard let chunks = try? await self.reassembler.ingest(chunk),
                          let value = try? self.codec.decode(
                            FinderMenuSnapshot.self,
                            from: chunks,
                            limit: .snapshot
                          )
                    else {
                        return
                    }
                    await MainActor.run { self.snapshot = value }
                }
            }
        )
        observers.append(
            notifications.addObserver(
                forName: names.actionAcknowledgement,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let value = notification.userInfo?["requestID"] as? String,
                      let requestID = UUID(uuidString: value),
                      self.pendingFeedback?.requestID == requestID
                else {
                    return
                }
                self.pendingFeedback = nil
            }
        )
    }

    private func postExtensionHeartbeat() {
        notifications.postNotificationName(
            names.extensionHeartbeat,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func activateContainerApp(completion: (@Sendable () -> Void)? = nil) {
        if let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: baseBundleID)
            .first
        {
            application.activate(options: [.activateAllWindows])
            completion?()
            return
        }

        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        ) { _, _ in
            completion?()
        }
    }
}
