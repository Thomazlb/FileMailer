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
        appLanguage = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        ) ?? .system
        persistence = try? PersistenceController()
        oauthStore = KeychainOAuthStateStore(baseBundleID: AppConfiguration.baseBundleID)
        tokenProvider = AppAuthTokenProvider(store: oauthStore)
        mailSender = GmailMailSender()
        analyzer = DefaultFileAnalyzer()
        temporaryFiles = try? TemporaryFileManager()
        do {
            let store = try DriveTransferStore()
            driveTransferStore = store
            driveTransfers = GoogleDriveTransferCoordinator(
                tokenProvider: tokenProvider,
                store: store
            )
        } catch {
            driveTransferStore = nil
            driveTransfers = nil
        }
        reload()
        if persistence == nil {
            addDiagnostic(
                category: "persistence",
                message: "La base locale n’a pas pu être ouverte."
            )
        }
        snapshotObservers = [
            $recipients.sink { [weak self] _ in self?.requestSnapshotRefresh() },
            $visibleRecipientCount.sink { [weak self] _ in self?.requestSnapshotRefresh() }
        ]
        Task { await temporaryFiles?.cleanExpiredFiles(olderThan: 86_400) }
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
        } else {
            addDiagnostic(
                category: "drive",
                message: "Le stockage local des transferts Google Drive n’a pas pu être ouvert."
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
    }

    var interfaceLocale: Locale {
        appLanguage.locale
    }

    func localizedString(_ key: String) -> String {
        // The catalog's source language is French, so it does not generate a
        // dedicated fr.lproj bundle. Resolve French directly instead of falling
        // through to an arbitrary translated bundle such as English.
        if appLanguage == .french || appLanguage == .frenchCanada {
            return key
        }
        if appLanguage == .system,
           Locale.autoupdatingCurrent.language.languageCode?.identifier == "fr" {
            return key
        }
        guard appLanguage != .system,
              let path = Bundle.main.path(
                forResource: appLanguage.resourceIdentifier,
                ofType: "lproj"
              ),
              let bundle = Bundle(path: path)
        else {
            return Bundle.main.localizedString(
                forKey: key,
                value: key,
                table: nil
            )
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
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
                    message: "Le nettoyage de \(record.displayName) a échoué : \(description)"
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

    func openCompose(paths: [String], recipientID: RecipientID?) {
        let recipient = recipientID.flatMap { id in recipients.first { $0.id == id } }
        windows?.showCompose(paths: paths, recipient: recipient)
    }

    func openManualCompose() {
        windows?.showCompose(paths: [], recipient: nil)
    }

    func resumeDraft(_ draft: ComposeDraft) {
        windows?.showCompose(draft: draft)
    }

    func openFilesCompose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.prompt = String(localized: "Ajouter")
        guard panel.runModal() == .OK else { return }
        openCompose(paths: panel.urls.map(\.path), recipientID: nil)
    }

    func finderSnapshot(now: Date = Date()) -> FinderMenuSnapshot {
        return FinderSnapshotBuilder().makeSnapshot(
            recipients: recipients,
            ownAddresses: [],
            visibleCount: visibleRecipientCount,
            now: now
        )
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
        let accountLines = accounts.map {
            "\($0.displayName ?? "Compte") •••@\(Self.maskedDomain($0.email)) [\($0.authStatus.rawValue)]"
        }
        let errorLines = diagnostics.suffix(30).map {
            "\($0.date.formatted()) [\($0.category)] \($0.message)"
        }
        return """
        \(AppConfiguration.appName) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
        macOS \(process.operatingSystemVersionString)
        Architecture: \(Self.architecture)
        Extension heartbeat: \(lastExtensionHeartbeat?.formatted() ?? "absent")
        Snapshot: \(lastSnapshotDate?.formatted() ?? "absent")
        IPC schema: \(IPCCodec.schemaVersion)
        Apple Intelligence: \(FoundationModelAvailability.current)
        Golden Gate: \(GoldenGateFeatureStatus.current)
        Limites: Finder 50, destinataires \(visibleRecipientCount), texte 1 MiB

        Comptes:
        \(accountLines.joined(separator: "\n"))

        Erreurs nettoyées:
        \(errorLines.joined(separator: "\n"))
        """
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
                with: "[adresse masquée]",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"/Users/[^\s]+"#,
                with: "[chemin masqué]",
                options: .regularExpression
            )
    }

    private static func maskedDomain(_ email: String) -> String {
        email.split(separator: "@").last.map(String.init) ?? "masqué"
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
