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
        .environment(\.layoutDirection, viewModel.interfaceLocale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
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
            "Unable to Complete the Operation",
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
                    "Describe How to Rewrite the Message…",
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
                            "Rewrite",
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
                .help("Rewrite Using This Instruction")
                .accessibilityLabel("Rewrite")

                Button {
                    closeRevisionEditor()
                } label: {
                    if compact {
                        Image(systemName: "xmark")
                    } else {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
                .help("Close Rewrite Instruction")
                .accessibilityLabel("Cancel")
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
                            LocalizedStringKey(viewModel.isGenerating || viewModel.isAnalyzing
                                ? "Stop" : "Regenerate"),
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
                    LocalizedStringKey(viewModel.isGenerating || viewModel.isAnalyzing
                        ? "Stop Writing"
                        : (viewModel.usesAppleIntelligence
                            ? "Give Apple Intelligence an Instruction"
                            : "Restart local draft"))
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
                        LocalizedStringKey(viewModel.isSending ? "Sending…" : "Send"),
                        systemImage: viewModel.isSending
                            ? "hourglass"
                            : "paperplane"
                    )
                }
            }
            .disabled(!viewModel.canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help(LocalizedStringKey(viewModel.isSending ? "Sending" : "Send Message"))
            .accessibilityLabel(LocalizedStringKey(viewModel.isSending ? "Sending" : "Send"))
            .accessibilityHint("Sends the visible message after review")
        }
        .frame(maxWidth: .infinity)
    }

    private var recipientFields: some View {
        VStack(spacing: 0) {
            fieldRow("From") {
                Picker(
                    "Sender Account",
                    selection: Binding(
                        get: { viewModel.draft.senderID },
                        set: viewModel.selectSender
                    )
                ) {
                    if viewModel.accounts.isEmpty {
                        Text("No Gmail account").tag(Optional<GmailAccountID>.none)
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

            fieldRow("To") {
                EmailTokenField(
                    addresses: Binding(
                        get: { viewModel.draft.to },
                        set: { viewModel.setRecipients($0, field: .to) }
                    ),
                    input: Binding(
                        get: { viewModel.recipientInput(for: .to) },
                        set: { viewModel.setRecipientInput($0, field: .to) }
                    ),
                    placeholder: "E-mail address"
                )
                .frame(height: 26)

                Button(LocalizedStringKey(viewModel.showCc ? "Hide Cc" : "Cc")) {
                    withAnimation(.snappy(duration: 0.18)) {
                        viewModel.showCc.toggle()
                    }
                }
                .buttonStyle(.link)

                Button(LocalizedStringKey(viewModel.showBcc ? "Hide Bcc" : "Bcc")) {
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
                        placeholder: "Cc label"
                    )
                    .frame(height: 26)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if viewModel.showBcc {
                fieldDivider
                fieldRow("Bcc") {
                    EmailTokenField(
                        addresses: Binding(
                            get: { viewModel.draft.bcc },
                            set: { viewModel.setRecipients($0, field: .bcc) }
                        ),
                        input: Binding(
                            get: { viewModel.recipientInput(for: .bcc) },
                            set: { viewModel.setRecipientInput($0, field: .bcc) }
                        ),
                        placeholder: "Bcc label"
                    )
                    .frame(height: 26)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            fieldDivider

            fieldRow("Subject") {
                TextField(
                    "Add a Subject",
                    text: Binding(
                        get: { viewModel.draft.subject },
                        set: viewModel.updateSubject
                    )
                )
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .accessibilityIdentifier("compose-subject")
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
                .frame(width: 76, alignment: .trailing)
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
                Text(viewModel.attachmentCountText)
                .font(.caption.weight(.medium))
                Spacer()
                Text(viewModel.totalAttachmentSize.formatted(.byteCount(style: .file).locale(viewModel.interfaceLocale)))
                .font(.caption)
                .foregroundStyle(
                    viewModel.directAttachmentSize > AttachmentDeliveryPolicy.directAttachmentLimit
                        ? .red
                        : .secondary
                )
                if viewModel.hasGoogleDriveAttachments
                    && !viewModel.selectedAccountHasGoogleDriveAccess {
                    Button(
                        LocalizedStringKey(viewModel.isAuthorizingDrive
                            ? "Authorisation…" : "Allow Google Drive")
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
                .help("Add Attachment")
                .accessibilityLabel(Text("Add Attachment"))
                .accessibilityIdentifier("add-attachment")
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
            Picker("Language", selection: $viewModel.language) {
                Text("Application language").tag(DraftLanguage.automatic)
                ForEach(DraftLanguage.allCases.filter { $0 != .automatic }) { language in
                    Text(verbatim: language.nativeDisplayName).tag(language)
                }
            }
            .accessibilityIdentifier("draft-language-picker")
            .labelsHidden()
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)

            Picker("Tone", selection: $viewModel.tone) {
                Text("Concise").tag(DraftTone.concise)
                Text("Professional").tag(DraftTone.professional)
                Text("Friendly").tag(DraftTone.friendly)
                Text("Neutral").tag(DraftTone.neutral)
            }
            .labelsHidden()
            .frame(width: 150)

            Button("Write manually") {
                viewModel.useManualMode()
            }
            .buttonStyle(.link)

            Spacer()

            if let suggestion = viewModel.suggestion {
                Button("Apply Suggestion") {
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
                        LocalizedStringKey(usesAppleIntelligence
                            ? "Apple Intelligence on This Mac" : "Local Processing")
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
