import AppKit
import Combine
import FileMailerCore
import FinderSync
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var recipients: [RecipientProfile] = []
    @Published private(set) var accounts: [GmailAccountSummary] = []
    @Published private(set) var pendingDrafts: [ComposeDraft] = []
    @Published var visibleRecipientCount = 5
    @Published var autosaveDrafts = false
    @Published var launchAtLogin = false
    @Published var appLanguage: AppLanguage
    @Published var lastExtensionHeartbeat: Date?
    @Published var lastSnapshotDate: Date?
    @Published var diagnostics: [SanitizedDiagnostic] = []
    @Published var onboardingPresented = false

    let persistence: PersistenceController?
    let fileAccess: FileAccessController
    let oauthStore: KeychainOAuthStateStore
    let tokenProvider: AppAuthTokenProvider
    let mailSender: GmailMailSender
    let analyzer: DefaultFileAnalyzer
    let temporaryFiles: TemporaryFileManager?
    let driveTransferStore: DriveTransferStore?
    let driveTransfers: GoogleDriveTransferCoordinator?
    private(set) lazy var oauthCoordinator = GoogleOAuthCoordinator(
        store: oauthStore
    ) {
        NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible)
    }

    weak var windows: WindowCoordinator?
    private var snapshotObservers: [AnyCancellable] = []
    private var driveCleanupScheduler: DriveCleanupScheduler?

    init() {
        #if DEBUG
        let isUITesting = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--ui-testing-") }
        if isUITesting, let language = ProcessInfo.processInfo.environment["FILEMAILER_TEST_LANGUAGE"] {
            UserDefaults.standard.set(language, forKey: "appLanguage")
        }
        #else
        let isUITesting = false
        #endif
        appLanguage = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        ) ?? .system
        #if DEBUG
        let persistReviewGrants = isUITesting
            && ProcessInfo.processInfo.environment["FILEMAILER_TEST_PERSIST_FILE_ACCESS"] == "1"
        fileAccess = FileAccessController(
            inMemory: isUITesting && !persistReviewGrants,
            storeName: isUITesting ? "ReviewFileAccess" : "FileAccess"
        )
        #else
        fileAccess = FileAccessController(inMemory: false)
        #endif
        persistence = try? PersistenceController(inMemory: isUITesting)
        oauthStore = KeychainOAuthStateStore(baseBundleID: AppConfiguration.baseBundleID)
        tokenProvider = AppAuthTokenProvider(store: oauthStore)
        mailSender = GmailMailSender()
        analyzer = DefaultFileAnalyzer()
        temporaryFiles = try? TemporaryFileManager()
        if isUITesting {
            driveTransferStore = nil
            driveTransfers = nil
        } else {
            do {
                let store = try DriveTransferStore()
                driveTransferStore = store
                driveTransfers = GoogleDriveTransferCoordinator(tokenProvider: tokenProvider, store: store)
            } catch {
                driveTransferStore = nil
                driveTransfers = nil
            }
        }
        reload()
        if persistence == nil {
            addDiagnostic(
                category: "persistence",
                message: localizedString("The local database could not be opened.")
            )
        }
        snapshotObservers = [
            $recipients.sink { [weak self] _ in self?.requestSnapshotRefresh() },
            $visibleRecipientCount.sink { [weak self] _ in self?.requestSnapshotRefresh() }
        ]
        if !isUITesting { Task { await temporaryFiles?.cleanExpiredFiles(olderThan: 86_400) } }
        if driveTransfers != nil {
            driveCleanupScheduler = DriveCleanupScheduler(
                identifier: "org.filemailer.FileMailer.drive-cleanup"
            ) { [weak self] in
                await self?.cleanExpiredDriveTransfers()
            }
            driveCleanupScheduler?.start()
            Task { [weak self] in
                await self?.cleanExpiredDriveTransfers()
            }
        } else if !isUITesting {
            addDiagnostic(
                category: "drive",
                message: localizedString("Local storage for Google Drive transfers could not be opened.")
            )
        }
    }

    func reload() {
        do {
            recipients = try persistence?.recipients() ?? []
            accounts = try persistence?.accounts() ?? []
            pendingDrafts = try persistence?.pendingDrafts() ?? []
            if let settings = try persistence?.settings() {
                visibleRecipientCount = min(max(settings.visibleRecipientCount, 1), 10)
                autosaveDrafts = settings.autosaveDrafts
                launchAtLogin = settings.launchAtLogin
            }
        } catch {
            addDiagnostic(category: "persistence", message: error.localizedDescription)
        }
    }

    func addOrUpdateRecipient(_ recipient: RecipientProfile) throws {
        try persistence?.upsert(recipient: recipient)
        reload()
    }

    func deleteRecipient(_ recipient: RecipientProfile) throws {
        try persistence?.delete(recipientID: recipient.id)
        reload()
    }

    func reorderPinned(from source: IndexSet, to destination: Int) {
        var pinned = recipients.filter(\.isPinned)
        pinned.move(fromOffsets: source, toOffset: destination)
        for (index, var recipient) in pinned.enumerated() {
            recipient.pinOrder = index
            try? persistence?.upsert(recipient: recipient)
        }
        reload()
    }

    func saveVisibleCount(_ value: Int) {
        visibleRecipientCount = min(max(value, 1), 10)
        do {
            let settings = try persistence?.settings()
            settings?.visibleRecipientCount = visibleRecipientCount
            try persistence?.container.mainContext.save()
        } catch {
            addDiagnostic(category: "settings", message: error.localizedDescription)
        }
    }

    func saveAutosaveDrafts(_ enabled: Bool) {
        autosaveDrafts = enabled
        do {
            if !enabled {
                try persistence?.deleteAllPendingDrafts()
            }
            let settings = try persistence?.settings()
            settings?.autosaveDrafts = enabled
            try persistence?.container.mainContext.save()
            reload()
        } catch {
            addDiagnostic(category: "settings", message: error.localizedDescription)
        }
    }

    func clearPendingDrafts() {
        do {
            try persistence?.deleteAllPendingDrafts()
            reload()
        } catch {
            addDiagnostic(category: "draft", message: error.localizedDescription)
        }
    }

    func saveAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "appLanguage")
        } else {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        }
        windows?.refreshLocalizedTitles()
        NativeMenuLocalizer.shared.refresh()
        requestSnapshotRefresh()
    }

    var interfaceLocale: Locale {
        appLanguage.locale
    }

    func localizedString(_ key: String) -> String {
        localization.string(key)
    }

    var localization: FileMailerLocalization {
        FileMailerLocalization(languageIdentifier: appLanguage.resolvedIdentifier)
    }

    func addGoogleAccount() async {
        do {
            let account = try await oauthCoordinator.authorize(
                clientID: AppConfiguration.googleClientID,
                redirectScheme: AppConfiguration.googleRedirectScheme
            )
            var value = account
            if accounts.isEmpty { value.isDefault = true }
            try persistence?.upsert(account: value)
            reload()
        } catch {
            addDiagnostic(category: "oauth", message: error.localizedDescription)
            windows?.presentError(error)
        }
    }

    func grantGoogleDriveAccess(for account: GmailAccountSummary) async throws {
        var authorized = try await oauthCoordinator.authorize(
            clientID: AppConfiguration.googleClientID,
            redirectScheme: AppConfiguration.googleRedirectScheme,
            additionalScopes: [GoogleOAuthCoordinator.driveFileScope],
            loginHint: account.email
        )
        guard authorized.id == account.id else {
            throw GoogleDriveError.authorizationRequired
        }
        authorized.isDefault = account.isDefault
        authorized.signature = account.signature
        try persistence?.upsert(account: authorized)
        reload()
    }

    func cleanExpiredDriveTransfers() async {
        guard let driveTransfers else { return }
        let outcomes = await driveTransfers.cleanDueTransfers()
        for outcome in outcomes {
            if case let .failed(record, description) = outcome {
                addDiagnostic(
                    category: "drive-cleanup",
                    message: "Cleanup of \(record.displayName) failed : \(description)"
                )
            }
        }
    }

    func removeAccount(_ account: GmailAccountSummary, revoke: Bool) async {
        do {
            try await oauthCoordinator.remove(accountID: account.id, revoke: revoke)
        } catch {
            addDiagnostic(category: "oauth", message: error.localizedDescription)
        }
        do {
            try await driveTransferStore?.removeAllMetadata(for: account.id)
        } catch {
            addDiagnostic(category: "drive", message: error.localizedDescription)
        }
        do {
            try persistence?.removeAccountMetadata(accountID: account.id)
            reload()
        } catch {
            addDiagnostic(category: "persistence", message: error.localizedDescription)
        }
    }

    func setDefaultAccount(_ accountID: GmailAccountID) {
        for var account in accounts {
            account.isDefault = account.id == accountID
            try? persistence?.upsert(account: account)
        }
        reload()
    }

    func setLaunchAtLogin(_ enabled: Bool) async {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            let settings = try persistence?.settings()
            settings?.launchAtLogin = launchAtLogin
            try persistence?.container.mainContext.save()
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            addDiagnostic(category: "login", message: error.localizedDescription)
        }
    }

    func openFinderCompose(paths: [String], recipientID: RecipientID?) throws {
        guard let selection = try fileAccess.finderSelection(
            paths: paths, localization: FileMailerLocalization(languageIdentifier: appLanguage.resolvedIdentifier)
        ) else { return }
        showCompose(selection: selection, recipientID: recipientID)
    }

    func openUserSelectedFiles(_ urls: [URL]) {
        do {
            let selection = try fileAccess.userSelected(urls)
            showCompose(selection: selection, recipientID: nil)
        } catch {
            windows?.presentError(error)
        }
    }

    private func showCompose(selection: FileAccessController.Selection, recipientID: RecipientID?) {
        let recipient = recipientID.flatMap { id in recipients.first { $0.id == id } }
        windows?.showCompose(urls: selection.urls, recipient: recipient, leases: selection.leases)
    }

    func openManualCompose() {
        windows?.showCompose(urls: [], recipient: nil)
    }

    func resumeDraft(_ draft: ComposeDraft) {
        windows?.showCompose(draft: draft)
    }

    func openFilesCompose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.prompt = localizedString("Add")
        guard panel.runModal() == .OK else { return }
        openUserSelectedFiles(panel.urls)
    }

    func finderSnapshot(now: Date = Date()) -> FinderMenuSnapshot {
        var snapshot = FinderSnapshotBuilder().makeSnapshot(
            recipients: recipients,
            ownAddresses: [],
            visibleCount: visibleRecipientCount,
            now: now
        )
        snapshot.languageIdentifier = appLanguage == .system ? nil : appLanguage.resolvedIdentifier
        return snapshot
    }

    func addDiagnostic(category: String, message: String) {
        let sanitized = Self.sanitize(message)
        diagnostics.append(
            SanitizedDiagnostic(
                date: Date(),
                category: category,
                message: sanitized
            )
        )
        AppLogger.sanitizedError(category: category, message: sanitized)
        if diagnostics.count > 100 {
            diagnostics.removeFirst(diagnostics.count - 100)
        }
    }

    func diagnosticReport() -> String {
        let process = ProcessInfo.processInfo
        let date = { (value: Date?) in
            value?.formatted(.dateTime.locale(self.interfaceLocale)) ?? self.localizedString("Absent")
        }
        let accountLines = accounts.map {
            "\($0.displayName ?? localizedString("Account")) •••@\(Self.maskedDomain($0.email))"
                + " [\($0.authStatus.rawValue)]"
        }
        let errorLines = diagnostics.suffix(30).map {
            "\($0.date.formatted(.dateTime.locale(interfaceLocale))) [\($0.category)] \($0.message)"
        }
        let status: String = switch FoundationModelAvailability.current {
        case .available: "On Device"
        case .unsupportedSystemVersion: "Deterministic draft on macOS 26"
        case .deviceNotEligible: "Device Not Eligible"
        case .appleIntelligenceDisabled: "Disabled"
        case .modelNotReady: "Model Not Ready"
        }
        return [
            "\(AppConfiguration.appName) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")",
            "macOS \(process.operatingSystemVersionString)",
            "\(localizedString("Architecture")): \(Self.architecture)",
            "\(localizedString("Presence signal")): \(date(lastExtensionHeartbeat))",
            "\(localizedString("Latest Snapshot")): \(date(lastSnapshotDate))",
            "\(localizedString("IPC Schema")): \(IPCCodec.schemaVersion)",
            "Apple Intelligence: \(localizedString(status))",
            "Golden Gate: \(localizedString("Compiled"))",
            localization.format("Limits: Finder 50, recipients %@, text 1 MiB", String(visibleRecipientCount)),
            "", localizedString("Accounts"), accountLines.joined(separator: "\n"),
            "", localizedString("Sanitized errors"), errorLines.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    private func requestSnapshotRefresh() {
        Task { @MainActor in
            await Task.yield()
            NotificationCenter.default.post(
                name: .fileMailerSnapshotNeedsRefresh,
                object: nil
            )
        }
    }

    private static func sanitize(_ input: String) -> String {
        input
            .replacingOccurrences(
                of: #"(?i)bearer\s+[A-Za-z0-9._~+/=-]+"#,
                with: "Bearer [REDACTED]",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
                with: "[redacted address]",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"/Users/[^\s]+"#,
                with: "[redacted path]",
                options: .regularExpression
            )
    }

    private static func maskedDomain(_ email: String) -> String {
        email.split(separator: "@").last.map(String.init) ?? "redacted"
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "inconnue"
        #endif
    }
}

struct SanitizedDiagnostic: Identifiable {
    let id = UUID()
    let date: Date
    let category: String
    let message: String
}

extension Notification.Name {
    static let fileMailerSnapshotNeedsRefresh = Notification.Name(
        "FileMailerSnapshotNeedsRefresh"
    )
}
