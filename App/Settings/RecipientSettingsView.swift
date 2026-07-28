import FileMailerCore
import SwiftUI

struct RecipientSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var editing: RecipientProfile?
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.recipients) { recipient in
                    RecipientRow(
                        recipient: recipient,
                        onTogglePin: { togglePin(recipient) },
                        onEdit: { editing = recipient },
                        onDelete: { delete(recipient) }
                    )
                }
                .onMove(perform: model.reorderPinned)
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .overlay {
                if model.recipients.isEmpty {
                    ContentUnavailableView(
                        "Aucun destinataire",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Ajoutez les personnes que vous contactez le plus souvent.")
                    )
                }
            }

            Divider()
            HStack {
                Button {
                    isAdding = true
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                Spacer()
                Text("Aperçu Finder: \(finderPreview)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .background(Color.black)
        .navigationTitle("Destinataires")
        .sheet(isPresented: $isAdding) {
            RecipientEditor(
                recipient: nil,
                accounts: model.accounts,
                onSave: save,
                onCancel: { isAdding = false }
            )
        }
        .sheet(item: $editing) { recipient in
            RecipientEditor(
                recipient: recipient,
                accounts: model.accounts,
                onSave: save,
                onCancel: { editing = nil }
            )
        }
        .alert(
            "Erreur",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var finderPreview: String {
        model.finderSnapshot().recipients.map(\.title).joined(separator: ", ")
    }

    private func save(_ recipient: RecipientProfile) {
        do {
            try model.addOrUpdateRecipient(recipient)
            isAdding = false
            editing = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func togglePin(_ recipient: RecipientProfile) {
        var value = recipient
        value.isPinned.toggle()
        value.pinOrder = value.isPinned
            ? (model.recipients.compactMap(\.pinOrder).max() ?? -1) + 1
            : nil
        try? model.addOrUpdateRecipient(value)
    }

    private func delete(_ recipient: RecipientProfile) {
        do {
            try model.deleteRecipient(recipient)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RecipientRow: View {
    let recipient: RecipientProfile
    let onTogglePin: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onTogglePin) {
                Image(systemName: recipient.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recipient.isPinned ? "Désépingler" : "Épingler")
            VStack(alignment: .leading) {
                Text(recipient.displayName)
                Text(recipient.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !recipient.isEnabled {
                Text("Masqué")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Modifier", action: onEdit)
            Button("Supprimer", role: .destructive, action: onDelete)
        }
        .padding(.vertical, 4)
    }
}

private struct RecipientEditor: View {
    @State private var id: RecipientID
    @State private var displayName: String
    @State private var email: String
    @State private var isPinned: Bool
    @State private var isEnabled: Bool
    @State private var preferredSenderID: GmailAccountID?
    @State private var tone: DraftTone
    @State private var customInstruction: String
    @State private var validationError: String?
    let accounts: [GmailAccountSummary]
    let onSave: (RecipientProfile) -> Void
    let onCancel: () -> Void

    init(
        recipient: RecipientProfile?,
        accounts: [GmailAccountSummary],
        onSave: @escaping (RecipientProfile) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _id = State(initialValue: recipient?.id ?? RecipientID())
        _displayName = State(initialValue: recipient?.displayName ?? "")
        _email = State(initialValue: recipient?.email ?? "")
        _isPinned = State(initialValue: recipient?.isPinned ?? false)
        _isEnabled = State(initialValue: recipient?.isEnabled ?? true)
        _preferredSenderID = State(initialValue: recipient?.preferredSenderID)
        _tone = State(initialValue: recipient?.preferredTone ?? .professional)
        _customInstruction = State(initialValue: recipient?.customInstruction ?? "")
        self.accounts = accounts
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Destinataire")
                .font(.title2.weight(.semibold))
            Form {
                TextField("Nom", text: $displayName)
                TextField("Adresse e-mail", text: $email)
                Toggle("Épinglé", isOn: $isPinned)
                Toggle("Visible dans le classement", isOn: $isEnabled)
                Picker("Compte préféré", selection: $preferredSenderID) {
                    Text("Automatique").tag(Optional<GmailAccountID>.none)
                    ForEach(accounts) { account in
                        Text(account.email).tag(Optional(account.id))
                    }
                }
                Picker("Ton", selection: $tone) {
                    Text("Concis").tag(DraftTone.concise)
                    Text("Professionnel").tag(DraftTone.professional)
                    Text("Amical").tag(DraftTone.friendly)
                    Text("Neutre").tag(DraftTone.neutral)
                }
                TextField("Préférence de rédaction", text: $customInstruction)
            }
            .scrollContentBackground(.hidden)
            if let validationError {
                Text(validationError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            HStack {
                Spacer()
                Button("Annuler", action: onCancel)
                Button("Enregistrer") {
                    do {
                        let address = try EmailAddress(email)
                        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            validationError = "Le nom est requis."
                            return
                        }
                        onSave(
                            RecipientProfile(
                                id: id,
                                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                                email: address.address,
                                isPinned: isPinned,
                                isEnabled: isEnabled,
                                preferredSenderID: preferredSenderID,
                                preferredTone: tone,
                                customInstruction: customInstruction.isEmpty ? nil : customInstruction
                            )
                        )
                    } catch {
                        validationError = error.localizedDescription
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Color.black)
    }
}
