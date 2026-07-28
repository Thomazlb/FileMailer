import AppKit
import FileMailerCore
import SwiftUI

@MainActor
struct ComposeView: View {
    @StateObject var viewModel: ComposeViewModel
    @State private var isDropTarget = false
    @State private var isRevisionEditorVisible = false
    @State private var revisionInstruction = ""
    @State private var authorizationDisclosure: GoogleAuthorizationPurpose?
    @FocusState private var isRevisionEditorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            recipientFields
            Divider()
            messageEditor
                .layoutPriority(1)
            Divider()
            attachmentStrip
            Divider()
            generationBar
        }
        .frame(minWidth: 760, minHeight: 620)
        .background(Color.black)
        .environment(\.locale, viewModel.interfaceLocale)
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.addAttachments(urls)
            return !urls.isEmpty
        } isTargeted: {
            isDropTarget = $0
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .alert(
            "Impossible de terminer l’opération",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(item: $authorizationDisclosure) { purpose in
            GoogleAuthorizationDisclosure(purpose: purpose) {
                if purpose == .drive {
                    viewModel.authorizeGoogleDrive()
                }
            }
        }
        .onChange(of: viewModel.sendSucceeded) {
            if viewModel.sendSucceeded {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    viewModel.close()
                }
            }
        }
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            actionBarRow(compact: false)
            actionBarRow(compact: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color.black)
    }

    private func actionBarRow(compact: Bool) -> some View {
        HStack(spacing: 12) {
            AIActivityPill(
                phase: viewModel.processingPhase,
                title: viewModel.activityTitle,
                usesAppleIntelligence: viewModel.usesAppleIntelligence,
                compact: compact
            )

            Spacer(minLength: 0)

            if isRevisionEditorVisible
                && !viewModel.isGenerating
                && !viewModel.isAnalyzing {
                TextField(
                    "Indiquez comment réécrire le message…",
                    text: $revisionInstruction
                )
                .focused($isRevisionEditorFocused)
                .lineLimit(1)
                .frame(
                    minWidth: compact ? 120 : 220,
                    idealWidth: compact ? 220 : 340,
                    maxWidth: compact ? .infinity : 380
                )
                .layoutPriority(1)
                .onSubmit(submitRevision)

                Button {
                    submitRevision()
                } label: {
                    if compact {
                        Image(systemName: viewModel.usesAppleIntelligence ? "apple.intelligence" : "arrow.clockwise")
                    } else {
                        Label(
                            "Relancer",
                            systemImage: viewModel.usesAppleIntelligence
                                ? "apple.intelligence"
                                : "arrow.clockwise"
                        )
                    }
                }
                .disabled(
                    revisionInstruction
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
                .help("Relancer la rédaction avec cette instruction")
                .accessibilityLabel("Relancer")

                Button {
                    closeRevisionEditor()
                } label: {
                    if compact {
                        Image(systemName: "xmark")
                    } else {
                        Label("Annuler", systemImage: "xmark")
                    }
                }
                .help("Fermer l’instruction de réécriture")
                .accessibilityLabel("Annuler")
            } else {
                Button {
                    handleRewriteButton()
                } label: {
                    if compact {
                        Image(
                            systemName: viewModel.isGenerating || viewModel.isAnalyzing
                                ? "stop.fill"
                                : (viewModel.usesAppleIntelligence
                                    ? "apple.intelligence"
                                    : "arrow.clockwise")
                        )
                        .contentTransition(.symbolEffect(.replace))
                    } else {
                        Label(
                            viewModel.isGenerating || viewModel.isAnalyzing
                                ? "Arrêter"
                                : "Régénérer",
                            systemImage: viewModel.isGenerating || viewModel.isAnalyzing
                                ? "stop.fill"
                                : (viewModel.usesAppleIntelligence
                                    ? "apple.intelligence"
                                    : "arrow.clockwise")
                        )
                        .contentTransition(.symbolEffect(.replace))
                    }
                }
                .help(
                    viewModel.isGenerating || viewModel.isAnalyzing
                        ? "Arrêter la rédaction"
                        : (viewModel.usesAppleIntelligence
                            ? "Donner une instruction à Apple Intelligence"
                            : "Relancer le brouillon local")
                )
            }

            Button {
                viewModel.send()
            } label: {
                if compact {
                    Image(
                        systemName: viewModel.isSending
                            ? "hourglass"
                            : "paperplane"
                    )
                } else {
                    Label(
                        viewModel.isSending ? "Envoi…" : "Envoyer",
                        systemImage: viewModel.isSending
                            ? "hourglass"
                            : "paperplane"
                    )
                }
            }
            .disabled(!viewModel.canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help(viewModel.isSending ? "Envoi en cours" : "Envoyer le message")
            .accessibilityLabel(viewModel.isSending ? "Envoi en cours" : "Envoyer")
            .accessibilityHint("Envoie le message visible après validation")
        }
        .frame(maxWidth: .infinity)
    }

    private var recipientFields: some View {
        VStack(spacing: 0) {
            fieldRow("De") {
                Picker(
                    "Compte expéditeur",
                    selection: Binding(
                        get: { viewModel.draft.senderID },
                        set: viewModel.selectSender
                    )
                ) {
                    if viewModel.accounts.isEmpty {
                        Text("Aucun compte Gmail").tag(Optional<GmailAccountID>.none)
                    }
                    ForEach(viewModel.accounts) { account in
                        Text(account.displayName.map { "\($0) · \(account.email)" } ?? account.email)
                            .tag(Optional(account.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            fieldDivider

            fieldRow("À") {
                EmailTokenField(
                    addresses: Binding(
                        get: { viewModel.draft.to },
                        set: { viewModel.setRecipients($0, field: .to) }
                    ),
                    input: Binding(
                        get: { viewModel.recipientInput(for: .to) },
                        set: { viewModel.setRecipientInput($0, field: .to) }
                    ),
                    placeholder: "nom@exemple.fr"
                )
                .frame(height: 26)

                Button(viewModel.showCc ? "Masquer Cc" : "Cc") {
                    withAnimation(.snappy(duration: 0.18)) {
                        viewModel.showCc.toggle()
                    }
                }
                .buttonStyle(.link)

                Button(viewModel.showBcc ? "Masquer Cci" : "Cci") {
                    withAnimation(.snappy(duration: 0.18)) {
                        viewModel.showBcc.toggle()
                    }
                }
                .buttonStyle(.link)
            }

            if viewModel.showCc {
                fieldDivider
                fieldRow("Cc") {
                    EmailTokenField(
                        addresses: Binding(
                            get: { viewModel.draft.cc },
                            set: { viewModel.setRecipients($0, field: .cc) }
                        ),
                        input: Binding(
                            get: { viewModel.recipientInput(for: .cc) },
                            set: { viewModel.setRecipientInput($0, field: .cc) }
                        ),
                        placeholder: "Copie"
                    )
                    .frame(height: 26)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if viewModel.showBcc {
                fieldDivider
                fieldRow("Cci") {
                    EmailTokenField(
                        addresses: Binding(
                            get: { viewModel.draft.bcc },
                            set: { viewModel.setRecipients($0, field: .bcc) }
                        ),
                        input: Binding(
                            get: { viewModel.recipientInput(for: .bcc) },
                            set: { viewModel.setRecipientInput($0, field: .bcc) }
                        ),
                        placeholder: "Copie cachée"
                    )
                    .frame(height: 26)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            fieldDivider

            fieldRow("Objet") {
                TextField(
                    "Ajoutez un objet",
                    text: Binding(
                        get: { viewModel.draft.subject },
                        set: viewModel.updateSubject
                    )
                )
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
            }
        }
        .padding(.horizontal, 16)
        .background(Color.black)
    }

    private var fieldDivider: some View {
        Divider()
            .padding(.leading, 66)
    }

    private func fieldRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(title))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
            content()
        }
        .frame(minHeight: 36)
        .padding(.vertical, 2)
    }

    private var messageEditor: some View {
        PlainTextBodyEditor(
            text: Binding(
                get: { viewModel.draft.body },
                set: viewModel.updateBody
            ),
            isStreaming: viewModel.processingPhase == .writing
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .animation(.smooth(duration: 0.2), value: viewModel.processingPhase)
    }

    private var attachmentStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
                Text(
                    viewModel.draft.attachments.isEmpty
                        ? "Aucune pièce jointe"
                        : "\(viewModel.draft.attachments.count) pièce(s) jointe(s)"
                )
                .font(.caption.weight(.medium))
                Spacer()
                Text(ByteCountFormatter.string(
                    fromByteCount: viewModel.totalAttachmentSize,
                    countStyle: .file
                ))
                .font(.caption)
                .foregroundStyle(
                    viewModel.directAttachmentSize > AttachmentDeliveryPolicy.directAttachmentLimit
                        ? .red
                        : .secondary
                )
                if viewModel.hasGoogleDriveAttachments
                    && !viewModel.selectedAccountHasGoogleDriveAccess {
                    Button(
                        viewModel.isAuthorizingDrive
                            ? "Autorisation…"
                            : "Autoriser Google Drive"
                    ) {
                        authorizationDisclosure = .drive
                    }
                    .disabled(viewModel.isAuthorizingDrive || viewModel.selectedAccount == nil)
                    .buttonStyle(.link)
                }
                Button {
                    addAttachments()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Ajouter une pièce jointe")
            }
            .padding(.horizontal, 16)
            .frame(height: 38)

            if !viewModel.draft.attachments.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(viewModel.draft.attachments) { attachment in
                            AttachmentCard(
                                attachment: attachment,
                                analysis: viewModel.analyses[attachment.id],
                                driveUploadState: viewModel.driveUploadState(for: attachment),
                                onRemove: { viewModel.removeAttachment(attachment) },
                                onPreview: { viewModel.preview(attachment) },
                                onReveal: { viewModel.reveal(attachment) },
                                onCompress: { viewModel.compressFolder(attachment) },
                                onDeliveryModeChange: {
                                    viewModel.setDeliveryMode($0, for: attachment)
                                },
                                onDriveAccessExpiryChange: {
                                    viewModel.setDriveAccessExpiry($0, for: attachment)
                                },
                                onCustomDriveAccessExpiryChange: {
                                    viewModel.setCustomDriveAccessExpiry($0, for: attachment)
                                },
                                onDriveCleanupActionChange: {
                                    viewModel.setDriveCleanupAction($0, for: attachment)
                                },
                                onPrepareDrive: { viewModel.prepareDriveUpload(for: attachment) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.hidden)
                .frame(
                    height: attachmentCarouselHeight,
                    alignment: .top
                )
            }
        }
        .background(Color.black)
    }

    private var attachmentCarouselHeight: CGFloat {
        let attachments = viewModel.draft.attachments
        if attachments.contains(where: {
            $0.usesGoogleDrive && $0.driveAccessExpiry == .custom
        }) {
            return 214
        }
        if attachments.contains(where: \.usesGoogleDrive) {
            return 182
        }
        return 132
    }

    private var generationBar: some View {
        HStack(spacing: 10) {
            Picker("Langue", selection: $viewModel.language) {
                Text("Auto").tag(DraftLanguage.automatic)
                Text("Français").tag(DraftLanguage.french)
                Text("English").tag(DraftLanguage.english)
            }
            .labelsHidden()
            .frame(width: 100)

            Picker("Ton", selection: $viewModel.tone) {
                Text("Concis").tag(DraftTone.concise)
                Text("Professionnel").tag(DraftTone.professional)
                Text("Amical").tag(DraftTone.friendly)
                Text("Neutre").tag(DraftTone.neutral)
            }
            .labelsHidden()
            .frame(width: 150)

            Button("Écrire manuellement") {
                viewModel.useManualMode()
            }
            .buttonStyle(.link)

            Spacer()

            if let suggestion = viewModel.suggestion {
                Button("Appliquer la suggestion") {
                    _ = suggestion
                    viewModel.applySuggestion()
                }
            } else if !viewModel.progressText.isEmpty
                        && !viewModel.processingPhase.isActive {
                Text(viewModel.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.black)
    }

    private func handleRewriteButton() {
        if viewModel.isGenerating || viewModel.isAnalyzing {
            viewModel.useManualMode()
        } else {
            withAnimation(.snappy(duration: 0.18)) {
                isRevisionEditorVisible = true
            }
            Task { @MainActor in
                await Task.yield()
                isRevisionEditorFocused = true
            }
        }
    }

    private func submitRevision() {
        let instruction = revisionInstruction
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        viewModel.regenerate(replacing: .both, instruction: instruction)
        closeRevisionEditor()
    }

    private func closeRevisionEditor() {
        isRevisionEditorFocused = false
        revisionInstruction = ""
        withAnimation(.snappy(duration: 0.18)) {
            isRevisionEditorVisible = false
        }
    }

    private func addAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK {
            viewModel.addAttachments(panel.urls)
        }
    }
}

private struct AIActivityPill: View {
    let phase: ComposeViewModel.ProcessingPhase
    let title: String
    let usesAppleIntelligence: Bool
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            if phase.isActive {
                if usesAppleIntelligence {
                    SpinningAppleIntelligenceIcon()
                        .accessibilityLabel(Text(title))
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text(title))
                }
            } else {
                Image(
                    systemName: phase == .ready
                        ? "checkmark.circle.fill"
                        : (usesAppleIntelligence ? "apple.intelligence" : "text.badge.checkmark")
                )
                .foregroundStyle(
                    phase == .ready ? Color.green : Color.accentColor
                )
            }

            if !phase.isActive && !compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .contentTransition(.interpolate)
                    Text(
                        usesAppleIntelligence
                            ? "Apple Intelligence sur ce Mac"
                            : "Traitement local"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .animation(.smooth(duration: 0.22), value: phase)
    }

}

private struct SpinningAppleIntelligenceIcon: View {
    @State private var rotation = 0.0

    var body: some View {
        Image(systemName: "apple.intelligence")
            .font(.title3)
            .foregroundStyle(.tint)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(
                    .linear(duration: 1.15)
                        .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }
            }
    }
}
