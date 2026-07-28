import AppKit
import Combine
import FileMailerCore
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ComposeViewModel: ObservableObject, Identifiable {
    enum ProcessingPhase: Int, Equatable {
        case idle = -1
        case analyzing = 0
        case thinking = 1
        case writing = 2
        case ready = 3

        var statusSymbol: String {
            switch self {
            case .idle: "circle"
            case .analyzing: "doc.text.magnifyingglass"
            case .thinking: "apple.intelligence"
            case .writing: "text.cursor"
            case .ready: "checkmark.circle.fill"
            }
        }

        var isActive: Bool {
            self == .analyzing || self == .thinking || self == .writing
        }
    }

    enum ReplacementChoice {
        case subject
        case body
        case both
    }

    enum DriveUploadState: Equatable {
        case notRequested
        case needsAuthorization
        case uploading
        case ready
        case failed(String)
    }

    let id = UUID()
    @Published var draft: ComposeDraft
    @Published var analyses: [UUID: AttachmentAnalysis] = [:]
    @Published var isAnalyzing = false
    @Published var isGenerating = false
    @Published var isSending = false
    @Published var progressText = ""
    @Published private(set) var processingPhase: ProcessingPhase = .idle
    @Published var errorMessage: String?
    @Published var suggestion: GeneratedDraftSnapshot?
    @Published var showCc = false
    @Published var showBcc = false
    @Published private var recipientInputs: [RecipientField: String] = [:]
    @Published var language: DraftLanguage = .automatic
    @Published var tone: DraftTone
    @Published var sendSucceeded = false
    @Published private(set) var driveUploadStates: [UUID: DriveUploadState] = [:]
    @Published private(set) var isAuthorizingDrive = false

    @Published private(set) var accounts: [GmailAccountSummary]
    let usesAppleIntelligence: Bool
    var onClose: (() -> Void)?
    private unowned let model: AppModel
    private let revisionPolicy = DraftRevisionPolicy()
    private var analysisTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var activeGenerationID: UUID?
    private var sendTask: Task<Void, Never>?
    private var driveUploadTasks: [UUID: Task<Void, Never>] = [:]
    private var autosaveCancellable: AnyCancellable?
    private let recipientInstruction: String?
    private var hasHandledWindowClose = false

    init(model: AppModel, paths: [String], recipient: RecipientProfile?) {
        self.model = model
        let connectedAccounts = model.accounts.filter { $0.authStatus == .connected }
        accounts = connectedAccounts
        usesAppleIntelligence = FoundationModelAvailability.current == .available
        tone = recipient?.preferredTone ?? .professional
        recipientInstruction = recipient?.customInstruction
        let selectedAccount = Self.selectAccount(accounts: connectedAccounts, recipient: recipient)
        let recipientAddress = recipient.flatMap {
            try? EmailAddress($0.email, displayName: $0.displayName)
        }
        let attachments = paths.prefix(50).map(Self.attachment(for:))
        draft = ComposeDraft(
            senderID: selectedAccount?.id,
            to: recipientAddress.map { [$0] } ?? [],
            attachments: attachments,
            generationState: attachments.isEmpty ? .manual : .analyzing
        )
        configureAutosave()
        for attachment in draft.attachments where attachment.usesGoogleDrive {
            prepareDriveUpload(for: attachment)
        }
        if !attachments.isEmpty {
            startInitialAnalysisAndGeneration()
        }
    }

    init(model: AppModel, draft: ComposeDraft) {
        self.model = model
        accounts = model.accounts.filter { $0.authStatus == .connected }
        usesAppleIntelligence = FoundationModelAvailability.current == .available
        tone = .professional
        recipientInstruction = nil
        self.draft = draft
        self.draft.attachments = draft.attachments.map { attachment in
            guard attachment.contentType != "inode/directory",
                  AttachmentDeliveryPolicy.usesGoogleDriveByDefault(for: attachment)
            else {
                return attachment
            }
            var updated = attachment
            updated.deliveryMode = .googleDrive
            return updated
        }
        if !self.draft.attachments.isEmpty {
            processingPhase = .analyzing
            analysisTask = Task { [weak self] in await self?.analyzeAttachments() }
        }
        configureAutosave()
        for attachment in self.draft.attachments where attachment.usesGoogleDrive {
            prepareDriveUpload(for: attachment)
        }
    }

    deinit {
        analysisTask?.cancel()
        generationTask?.cancel()
        sendTask?.cancel()
        for task in driveUploadTasks.values { task.cancel() }
    }

    var selectedAccount: GmailAccountSummary? {
        accounts.first { $0.id == draft.senderID }
    }

    var interfaceLocale: Locale {
        model.interfaceLocale
    }

    var activityTitle: String {
        if processingPhase == .idle {
            return model.localizedString("Prêt à rédiger")
        }
        if !usesAppleIntelligence
            && (processingPhase == .thinking || processingPhase == .writing) {
            return model.localizedString("Préparation du brouillon")
        }
        switch processingPhase {
        case .idle:
            return ""
        case .analyzing:
            return model.localizedString("Analyse du contenu des fichiers")
        case .thinking:
            return model.localizedString("Apple Intelligence réfléchit")
        case .writing:
            return model.localizedString("Rédaction de l’objet et du message")
        case .ready:
            return model.localizedString("Brouillon prêt à relire")
        }
    }

    var totalAttachmentSize: Int64 {
        draft.attachments.reduce(0) { $0 + $1.size }
    }

    var directAttachmentSize: Int64 {
        draft.attachments
            .filter { $0.deliveryMode == .attachment }
            .reduce(0) { $0 + $1.size }
    }

    var hasGoogleDriveAttachments: Bool {
        draft.attachments.contains(where: \.usesGoogleDrive)
    }

    var selectedAccountHasGoogleDriveAccess: Bool {
        selectedAccount?.grantedScopes.contains(GoogleOAuthCoordinator.driveFileScope) == true
    }

    var sendButtonTitle: String {
        guard let email = selectedAccount?.email else {
            return String(localized: "Envoyer")
        }
        return String(localized: "Envoyer avec \(email)")
    }

    var canSend: Bool {
        !isSending
            && !isAnalyzing
            && !isGenerating
            && draft.senderID != nil
            && !draft.to.isEmpty
            && draft.to.count + draft.cc.count + draft.bcc.count <= 50
            && !draft.attachments.contains { $0.contentType == "inode/directory" }
            && directAttachmentSize <= AttachmentDeliveryPolicy.directAttachmentLimit
            && (!hasGoogleDriveAttachments || selectedAccountHasGoogleDriveAccess)
            && (!draft.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func updateSubject(_ value: String) {
        guard draft.subject != value else { return }
        draft.subject = value
        draft.userRevision &+= 1
    }

    func updateBody(_ value: String) {
        guard draft.body != value else { return }
        draft.body = value
        draft.userRevision &+= 1
    }

    func setRecipients(_ values: [EmailAddress], field: RecipientField) {
        switch field {
        case .to:
            guard draft.to != values else { return }
            draft.to = values
        case .cc:
            guard draft.cc != values else { return }
            draft.cc = values
        case .bcc:
            guard draft.bcc != values else { return }
            draft.bcc = values
        }
        draft.userRevision &+= 1
    }

    func recipientInput(for field: RecipientField) -> String {
        recipientInputs[field, default: ""]
    }

    func setRecipientInput(_ value: String, field: RecipientField) {
        recipientInputs[field] = value
    }

    func selectSender(_ accountID: GmailAccountID?) {
        guard draft.senderID != accountID else { return }
        draft.senderID = accountID
        for index in draft.attachments.indices where draft.attachments[index].usesGoogleDrive {
            let attachment = draft.attachments[index]
            if attachment.driveFile?.accountID != accountID {
                if let preparedFile = attachment.driveFile {
                    Task { [weak self] in
                        do {
                            try await self?.model.driveTransfers?.discardPreparedFile(preparedFile)
                        } catch {
                            self?.model.addDiagnostic(category: "drive", message: error.localizedDescription)
                        }
                    }
                }
                draft.attachments[index].driveFile = nil
                driveUploadStates[attachment.id] = selectedAccountHasGoogleDriveAccess
                    ? .notRequested
                    : .needsAuthorization
            }
        }
        if selectedAccountHasGoogleDriveAccess {
            for attachment in draft.attachments where attachment.usesGoogleDrive {
                prepareDriveUpload(for: attachment)
            }
        }
        draft.userRevision &+= 1
    }

    func deliveryMode(for attachment: ComposeAttachment) -> AttachmentDeliveryMode {
        attachment.deliveryMode
    }

    func setDeliveryMode(_ mode: AttachmentDeliveryMode, for attachment: ComposeAttachment) {
        guard let index = draft.attachments.firstIndex(where: { $0.id == attachment.id }) else {
            return
        }
        let requiresGoogleDrive = AttachmentDeliveryPolicy.requiresLinkDelivery(
            for: draft.attachments[index]
        )
        let resolvedMode: AttachmentDeliveryMode = requiresGoogleDrive ? .googleDrive : mode
        if requiresGoogleDrive, mode == .attachment {
            errorMessage = model.localizedString(
                "Gmail bloque ce type de fichier. Utilisez le lien Google Drive proposé."
            )
        }
        guard draft.attachments[index].deliveryMode != resolvedMode else { return }

        let preparedFile = draft.attachments[index].driveFile
        draft.attachments[index].deliveryMode = resolvedMode
        if resolvedMode == .attachment {
            driveUploadTasks[attachment.id]?.cancel()
            driveUploadTasks[attachment.id] = nil
            draft.attachments[index].driveFile = nil
            driveUploadStates[attachment.id] = .notRequested
            if let preparedFile {
                Task { [weak self] in
                    do {
                        try await self?.model.driveTransfers?.discardPreparedFile(preparedFile)
                    } catch {
                        self?.model.addDiagnostic(
                            category: "drive",
                            message: error.localizedDescription
                        )
                    }
                }
            }
        } else if selectedAccountHasGoogleDriveAccess {
            prepareDriveUpload(for: draft.attachments[index])
        } else {
            driveUploadStates[attachment.id] = .needsAuthorization
        }
        draft.userRevision &+= 1
    }

    func setDriveAccessExpiry(_ expiry: DriveAccessExpiry, for attachment: ComposeAttachment) {
        guard let index = draft.attachments.firstIndex(where: { $0.id == attachment.id }) else {
            return
        }
        draft.attachments[index].driveAccessExpiry = expiry
        if expiry != .custom {
            draft.attachments[index].customDriveAccessExpiry = nil
        } else if draft.attachments[index].customDriveAccessExpiry == nil {
            draft.attachments[index].customDriveAccessExpiry = Calendar.current.date(
                byAdding: .day,
                value: 7,
                to: Date()
            )
        }
        if expiry != .never, draft.attachments[index].driveCleanupAction == .keep {
            draft.attachments[index].driveCleanupAction = .trash
        }
        draft.userRevision &+= 1
    }

    func setCustomDriveAccessExpiry(_ date: Date, for attachment: ComposeAttachment) {
        guard let index = draft.attachments.firstIndex(where: { $0.id == attachment.id }) else {
            return
        }
        draft.attachments[index].driveAccessExpiry = .custom
        draft.attachments[index].customDriveAccessExpiry = date
        if draft.attachments[index].driveCleanupAction == .keep {
            draft.attachments[index].driveCleanupAction = .trash
        }
        draft.userRevision &+= 1
    }

    func setDriveCleanupAction(_ action: DriveCleanupAction, for attachment: ComposeAttachment) {
        guard let index = draft.attachments.firstIndex(where: { $0.id == attachment.id }) else {
            return
        }
        draft.attachments[index].driveCleanupAction = action
        if action == .keep, draft.attachments[index].driveAccessExpiry != .never {
            draft.attachments[index].driveAccessExpiry = .never
            draft.attachments[index].customDriveAccessExpiry = nil
        } else if action != .keep, draft.attachments[index].driveAccessExpiry == .never {
            draft.attachments[index].driveAccessExpiry = .sevenDays
        }
        draft.userRevision &+= 1
    }

    func driveUploadState(for attachment: ComposeAttachment) -> DriveUploadState {
        if let state = driveUploadStates[attachment.id] {
            return state
        }
        if attachment.driveFile?.accountID == selectedAccount?.id {
            return .ready
        }
        if attachment.usesGoogleDrive && !selectedAccountHasGoogleDriveAccess {
            return .needsAuthorization
        }
        return .notRequested
    }

    func authorizeGoogleDrive() {
        guard let account = selectedAccount, !isAuthorizingDrive else { return }
        isAuthorizingDrive = true
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isAuthorizingDrive = false }
            do {
                try await model.grantGoogleDriveAccess(for: account)
                accounts = model.accounts.filter { $0.authStatus == .connected }
                for attachment in draft.attachments where attachment.usesGoogleDrive {
                    prepareDriveUpload(for: attachment)
                }
            } catch {
                errorMessage = error.localizedDescription
                model.addDiagnostic(category: "drive-oauth", message: error.localizedDescription)
            }
        }
    }

    func prepareDriveUpload(for attachment: ComposeAttachment) {
        guard attachment.usesGoogleDrive,
              let account = selectedAccount
        else {
            return
        }
        guard selectedAccountHasGoogleDriveAccess else {
            driveUploadStates[attachment.id] = .needsAuthorization
            return
        }
        if attachment.driveFile?.accountID == account.id {
            driveUploadStates[attachment.id] = .ready
            return
        }
        driveUploadTasks[attachment.id]?.cancel()
        let attachmentID = attachment.id
        driveUploadTasks[attachmentID] = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await prepareDriveReference(attachment, account: account)
            } catch is CancellationError {
                if driveUploadState(for: attachment) == .uploading {
                    driveUploadStates[attachmentID] = .notRequested
                }
            } catch {
                driveUploadStates[attachmentID] = .failed(error.localizedDescription)
                model.addDiagnostic(category: "drive-upload", message: error.localizedDescription)
            }
            driveUploadTasks[attachmentID] = nil
        }
    }

    private func prepareDriveReference(
        _ attachment: ComposeAttachment,
        account: GmailAccountSummary
    ) async throws -> DriveFileReference {
        if let prepared = attachment.driveFile, prepared.accountID == account.id {
            driveUploadStates[attachment.id] = .ready
            return prepared
        }
        guard selectedAccountHasGoogleDriveAccess,
              let driveTransfers = model.driveTransfers
        else {
            driveUploadStates[attachment.id] = .needsAuthorization
            throw GoogleDriveError.authorizationRequired
        }
        driveUploadStates[attachment.id] = .uploading
        do {
            let reference = try await driveTransfers.prepare(
                attachment: attachment,
                accountID: account.id
            )
            guard !Task.isCancelled,
                  let index = draft.attachments.firstIndex(where: { $0.id == attachment.id }),
                  draft.attachments[index].usesGoogleDrive,
                  draft.senderID == account.id
            else {
                try? await driveTransfers.discardPreparedFile(reference)
                throw CancellationError()
            }
            draft.attachments[index].driveFile = reference
            driveUploadStates[attachment.id] = .ready
            return reference
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            driveUploadStates[attachment.id] = .failed(error.localizedDescription)
            throw error
        }
    }

    func addAttachments(_ urls: [URL]) {
        let existing = Set(draft.attachments.map { $0.url.standardizedFileURL })
        for url in urls.prefix(max(0, 50 - draft.attachments.count))
            where !existing.contains(url.standardizedFileURL) {
            let attachment = Self.attachment(for: url.path)
            draft.attachments.append(attachment)
            if attachment.usesGoogleDrive {
                prepareDriveUpload(for: attachment)
            }
        }
        analysisTask?.cancel()
        processingPhase = .analyzing
        analysisTask = Task { [weak self] in await self?.analyzeAttachments() }
    }

    func removeAttachment(_ attachment: ComposeAttachment) {
        driveUploadTasks[attachment.id]?.cancel()
        driveUploadTasks[attachment.id] = nil
        draft.attachments.removeAll { $0.id == attachment.id }
        analyses.removeValue(forKey: attachment.id)
        driveUploadStates.removeValue(forKey: attachment.id)
        if let preparedFile = attachment.driveFile {
            Task { [weak self] in
                do {
                    try await self?.model.driveTransfers?.discardPreparedFile(preparedFile)
                } catch {
                    self?.model.addDiagnostic(category: "drive", message: error.localizedDescription)
                }
            }
        }
        if attachment.isTemporary {
            Task { await model.temporaryFiles?.remove(attachment.url) }
        }
        draft.userRevision &+= 1
    }

    func reveal(_ attachment: ComposeAttachment) {
        NSWorkspace.shared.activateFileViewerSelecting([attachment.url])
    }

    func preview(_ attachment: ComposeAttachment) {
        QuickLookPreviewCoordinator.shared.preview(attachment.url)
    }

    func compressFolder(_ attachment: ComposeAttachment) {
        guard attachment.contentType == "inode/directory" else { return }
        isAnalyzing = true
        processingPhase = .analyzing
        progressText = String(localized: "Compression du dossier…")
        Task {
            do {
                guard let destination = try await model.temporaryFiles?.makeTemporaryFile(
                    extension: "zip"
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let manifest = try await FolderArchiver().archive(
                    folder: attachment.url,
                    to: destination,
                    allowSensitiveFiles: false
                )
                let values = try destination.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]
                )
                var zip = ComposeAttachment(
                    url: destination,
                    displayName: attachment.displayName + ".zip",
                    contentType: "application/zip",
                    size: Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate,
                    isTemporary: true,
                    warning: manifest.excludedPaths.isEmpty
                        ? nil
                        : "\(manifest.excludedPaths.count) éléments exclus",
                    deliveryMode: .attachment
                )
                if AttachmentDeliveryPolicy.usesGoogleDriveByDefault(for: zip) {
                    zip.deliveryMode = .googleDrive
                }
                if let index = draft.attachments.firstIndex(where: { $0.id == attachment.id }) {
                    draft.attachments[index] = zip
                    if zip.usesGoogleDrive {
                        prepareDriveUpload(for: zip)
                    }
                }
                draft.userRevision &+= 1
                await analyzeAttachments()
            } catch {
                errorMessage = error.localizedDescription
            }
            isAnalyzing = false
            progressText = ""
        }
    }

    func analyzeAttachments(willGenerate: Bool = false) async {
        isAnalyzing = true
        processingPhase = .analyzing
        progressText = model.localizedString("Lecture du nom et du contenu des fichiers…")
        defer {
            isAnalyzing = false
            progressText = ""
            if processingPhase == .analyzing {
                processingPhase = willGenerate ? .thinking : .ready
            }
            if !isGenerating { draft.generationState = .manual }
        }
        do {
            let values = try await model.analyzer.analyze(
                urls: draft.attachments.map(\.url),
                policy: AnalysisPolicy()
            )
            for (index, analysis) in values.enumerated()
                where index < draft.attachments.count {
                analyses[draft.attachments[index].id] = analysis
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generate(
        replacing choice: ReplacementChoice = .both,
        instruction: String? = nil
    ) {
        invalidateGeneration()
        let generationID = UUID()
        activeGenerationID = generationID
        let startRevision = draft.userRevision
        let originalSubject = draft.subject
        let originalBody = draft.body
        let account = selectedAccount
        let revisionInstruction = instruction?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let request = DraftGenerationRequest(
            language: language,
            tone: tone,
            recipientName: draft.to.first?.displayName,
            senderName: account?.displayName,
            userPurpose: revisionInstruction?.isEmpty == false
                ? revisionInstruction
                : nil,
            customInstruction: recipientInstruction,
            analyses: draft.attachments.compactMap { analyses[$0.id] },
            signature: {
                let signature = account?.signature?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return signature?.isEmpty == false ? signature : account?.displayName
            }()
        )
        isGenerating = true
        processingPhase = .thinking
        draft.generationState = .generating
        progressText = usesAppleIntelligence
            ? model.localizedString("Apple Intelligence prépare le brouillon…")
            : model.localizedString("Préparation locale du brouillon…")
        generationTask = Task { [weak self] in
            guard let self else { return }
            let generator: any EmailDraftGenerating
            if usesAppleIntelligence, #available(macOS 27.0, *) {
                generator = GoldenGateDraftGenerator()
            } else {
                generator = DeterministicDraftGenerator()
            }
            do {
                for try await generated in generator.streamDraft(request: request) {
                    guard isCurrentGeneration(generationID), !Task.isCancelled else { return }
                    processingPhase = .writing
                    progressText = model.localizedString("Rédaction de l’objet et du message…")
                    var candidate = generated
                    if choice == .body { candidate.subject = originalSubject }
                    if choice == .subject { candidate.body = originalBody }
                    switch revisionPolicy.apply(
                        candidate,
                        generationStartedAt: startRevision,
                        to: &draft
                    ) {
                    case .applied:
                        break
                    case let .suggestion(value):
                        suggestion = value
                    }
                }
            } catch is CancellationError {
                guard isCurrentGeneration(generationID) else { return }
                draft.generationState = .manual
                completeGeneration(id: generationID, phase: .idle)
                return
            } catch {
                guard isCurrentGeneration(generationID) else { return }
                errorMessage = error.localizedDescription
                processingPhase = .writing
                let fallback = DeterministicDraftGenerator().generate(request)
                switch revisionPolicy.apply(
                    fallback,
                    generationStartedAt: startRevision,
                    to: &draft
                ) {
                case .applied:
                    break
                case let .suggestion(value):
                    suggestion = value
                }
            }
            completeGeneration(id: generationID, phase: .ready)
        }
    }

    func regenerate(
        replacing choice: ReplacementChoice = .both,
        instruction: String
    ) {
        analysisTask?.cancel()
        invalidateGeneration()
        analysisTask = Task { [weak self] in
            guard let self else { return }
            await analyzeAttachments(willGenerate: true)
            guard !Task.isCancelled else { return }
            generate(replacing: choice, instruction: instruction)
        }
    }

    func applySuggestion() {
        guard let suggestion else { return }
        draft.subject = suggestion.subject
        draft.body = suggestion.body
        draft.userRevision &+= 1
        draft.generationState = .generated
        self.suggestion = nil
    }

    func useManualMode() {
        analysisTask?.cancel()
        invalidateGeneration()
        isAnalyzing = false
        draft.generationState = .manual
        processingPhase = .idle
        progressText = ""
    }

    private func isCurrentGeneration(_ id: UUID) -> Bool {
        activeGenerationID == id
    }

    private func invalidateGeneration() {
        activeGenerationID = nil
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        progressText = ""
        if processingPhase == .thinking || processingPhase == .writing {
            processingPhase = .idle
        }
    }

    private func completeGeneration(id: UUID, phase: ProcessingPhase) {
        guard isCurrentGeneration(id) else { return }
        activeGenerationID = nil
        generationTask = nil
        isGenerating = false
        progressText = ""
        processingPhase = phase
    }

    func send() {
        guard canSend, let account = selectedAccount else { return }
        sendTask?.cancel()
        isSending = true
        errorMessage = nil
        progressText = model.localizedString("Vérification des pièces jointes…")
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Self.verifyUnchanged(draft.attachments)
                guard let sender = try? EmailAddress(
                    account.email,
                    displayName: account.displayName
                ) else {
                    throw GmailSendError.invalidAddress
                }
                let baseSnapshot = try draft.outboundSnapshot(from: sender)
                let driveRecipients = baseSnapshot.to + baseSnapshot.cc + baseSnapshot.bcc
                let driveAttachments = draft.attachments.filter(\.usesGoogleDrive)
                if !driveAttachments.isEmpty {
                    progressText = model.localizedString("Préparation des liens Google Drive…")
                }
                for attachment in driveAttachments {
                    let current = draft.attachments.first(where: { $0.id == attachment.id }) ?? attachment
                    let file = try await prepareDriveReference(current, account: account)
                    guard let updated = draft.attachments.first(where: { $0.id == attachment.id }) else {
                        throw CancellationError()
                    }
                    progressText = model.localizedString("Activation du lien Google Drive…")
                    let accessExpiresAt = updated.resolvedDriveAccessExpiry()
                    try await model.driveTransfers?.grantRecipientReaderAccess(
                        to: file,
                        recipients: driveRecipients,
                        expiresAt: accessExpiresAt
                    )
                    try await model.driveTransfers?.scheduleCleanup(
                        for: file,
                        displayName: updated.displayName,
                        action: updated.driveCleanupAction,
                        dueAt: accessExpiresAt
                    )
                }
                let snapshot = OutboundMessage(
                    id: baseSnapshot.id,
                    sender: baseSnapshot.sender,
                    to: baseSnapshot.to,
                    cc: baseSnapshot.cc,
                    bcc: baseSnapshot.bcc,
                    subject: baseSnapshot.subject,
                    body: Self.bodyWithDriveLinks(
                        baseSnapshot.body,
                        attachments: draft.attachments.filter(\.usesGoogleDrive),
                        heading: language == .english
                            ? "Files available via a Google Drive link:"
                            : "Fichiers disponibles via un lien Google Drive :"
                    ),
                    attachments: draft.attachments.filter { $0.deliveryMode == .attachment },
                    capturedRevision: baseSnapshot.capturedRevision
                )
                guard !snapshot.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !snapshot.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    throw OutboundMessageError.emptySubjectAndBody
                }
                guard let destination = try await model.temporaryFiles?.makeTemporaryFile(
                    extension: "eml"
                ) else {
                    throw MIMEError.writeFailure
                }
                progressText = model.localizedString("Construction du message…")
                let build = try await Task.detached {
                    try MIMEWriter().write(snapshot, to: destination)
                }.value
                progressText = model.localizedString("Envoi avec Gmail…")
                let receipt = try await GmailUploadCoordinator(
                    sender: model.mailSender,
                    tokenProvider: model.tokenProvider
                ).send(
                    messageFile: build.fileURL,
                    size: build.byteCount,
                    accountID: account.id
                )
                _ = receipt
                try model.persistence?.recordSuccessfulSend(
                    accountID: account.id,
                    recipients: snapshot.to + snapshot.cc + snapshot.bcc,
                    attachments: draft.attachments
                )
                try model.persistence?.deletePendingDraft(id: draft.id)
                await model.temporaryFiles?.remove(build.fileURL)
                for attachment in draft.attachments where attachment.isTemporary {
                    await model.temporaryFiles?.remove(attachment.url)
                }
                model.reload()
                sendSucceeded = true
                progressText = model.localizedString("Message envoyé")
            } catch {
                errorMessage = error.localizedDescription
                model.addDiagnostic(category: "send", message: error.localizedDescription)
                progressText = ""
            }
            isSending = false
        }
    }

    func close() {
        onClose?()
    }

    func handleWindowClose() {
        guard !hasHandledWindowClose else { return }
        hasHandledWindowClose = true
        analysisTask?.cancel()
        invalidateGeneration()
        if isSending {
            sendTask?.cancel()
            errorMessage = GmailSendError.ambiguousTimeout.localizedDescription
        }
        for task in driveUploadTasks.values {
            task.cancel()
        }
        driveUploadTasks.removeAll()
        if !sendSucceeded {
            for attachment in draft.attachments where attachment.usesGoogleDrive {
                guard let preparedFile = attachment.driveFile else { continue }
                Task { [weak self] in
                    do {
                        try await self?.model.driveTransfers?.discardPreparedFile(preparedFile)
                    } catch {
                        self?.model.addDiagnostic(
                            category: "drive-cleanup",
                            message: error.localizedDescription
                        )
                    }
                }
            }
        }
        Task {
            for attachment in draft.attachments where attachment.isTemporary {
                await model.temporaryFiles?.remove(attachment.url)
            }
        }
        if !model.autosaveDrafts {
            try? model.persistence?.deletePendingDraft(id: draft.id)
            model.reload()
        }
    }

    private func configureAutosave() {
        autosaveCancellable = $draft
            .dropFirst()
            .debounce(for: .milliseconds(700), scheduler: RunLoop.main)
            .sink { [weak self] draft in
                guard let self else { return }
                let hasContent = !draft.subject.isEmpty
                    || !draft.body.isEmpty
                    || !draft.to.isEmpty
                    || !draft.attachments.isEmpty
                do {
                    if model.autosaveDrafts, hasContent {
                        try model.persistence?.savePendingDraft(draft)
                    } else {
                        try model.persistence?.deletePendingDraft(id: draft.id)
                    }
                    model.reload()
                } catch {
                    model.addDiagnostic(
                        category: "draft",
                        message: error.localizedDescription
                    )
                }
            }
    }

    private func startInitialAnalysisAndGeneration() {
        processingPhase = .analyzing
        analysisTask = Task { [weak self] in
            guard let self else { return }
            await analyzeAttachments(willGenerate: true)
            guard !Task.isCancelled,
                  draft.userRevision == 0,
                  draft.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return
            }
            generate()
        }
    }

    private static func selectAccount(
        accounts: [GmailAccountSummary],
        recipient: RecipientProfile?
    ) -> GmailAccountSummary? {
        if let preferred = recipient?.preferredSenderID,
           let account = accounts.first(where: { $0.id == preferred }) {
            return account
        }
        return accounts.first(where: \.isDefault) ?? accounts.first
    }

    private static func attachment(for path: String) -> ComposeAttachment {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(
            forKeys: [
                .fileSizeKey, .contentTypeKey, .contentModificationDateKey,
                .isDirectoryKey
            ]
        )
        let directory = values?.isDirectory == true
        let size = Int64(values?.fileSize ?? 0)
        var attachment = ComposeAttachment(
            url: url,
            contentType: directory
                ? "inode/directory"
                : values?.contentType?.preferredMIMEType ?? "application/octet-stream",
            size: size,
            modificationDate: values?.contentModificationDate,
            deliveryMode: .attachment
        )
        if !directory, AttachmentDeliveryPolicy.usesGoogleDriveByDefault(for: attachment) {
            attachment.deliveryMode = .googleDrive
        }
        return attachment
    }

    private static func verifyUnchanged(_ attachments: [ComposeAttachment]) throws {
        for attachment in attachments {
            let values = try attachment.url.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey, .isReadableKey]
            )
            guard values.isReadable != false else {
                throw GmailSendError.fileAccessLost
            }
            let currentSize = Int64(values.fileSize ?? 0)
            let currentDate = values.contentModificationDate
            if currentSize != attachment.size
                || (attachment.modificationDate != nil && currentDate != attachment.modificationDate) {
                throw OutboundMessageError.attachmentChanged(attachment.displayName)
            }
        }
    }

    private static func bodyWithDriveLinks(
        _ body: String,
        attachments: [ComposeAttachment],
        heading: String
    ) -> String {
        let links = attachments.compactMap { attachment -> String? in
            guard let file = attachment.driveFile else { return nil }
            return "\(attachment.displayName) : \(file.webViewURL.absoluteString)"
        }
        guard !links.isEmpty else { return body }
        let prefix = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\n\n"
        return body + prefix + heading + "\n" + links.joined(separator: "\n")
    }
}

enum RecipientField: Hashable {
    case to
    case cc
    case bcc
}
