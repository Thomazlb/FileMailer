import FileMailerCore
import SwiftUI

struct AccountSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var accountToRemove: GmailAccountSummary?
    @State private var authorizationDisclosure: GoogleAuthorizationPurpose?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.accounts) { account in
                    HStack {
                        Image(systemName: account.authStatus == .connected ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(account.authStatus == .connected ? .green : .orange)
                        VStack(alignment: .leading) {
                            Text(account.displayName ?? account.email)
                            Text(account.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(scopeSummary(account))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle(
                            "Par défaut",
                            isOn: Binding(
                                get: { account.isDefault },
                                set: { enabled in
                                    if enabled { model.setDefaultAccount(account.id) }
                                }
                            )
                        )
                        .toggleStyle(.checkbox)
                        Button("Reconnecter") {
                            authorizationDisclosure = .gmail
                        }
                        Button("Supprimer", role: .destructive) {
                            accountToRemove = account
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .overlay {
                if model.accounts.isEmpty {
                    ContentUnavailableView(
                        "Aucun compte Gmail",
                        systemImage: "envelope.badge",
                        description: Text("Un compte est requis uniquement au moment d’envoyer.")
                    )
                }
            }
            Divider()
            HStack {
                Button {
                    authorizationDisclosure = .gmail
                } label: {
                    Label("Ajouter un compte", systemImage: "plus")
                }
                Spacer()
                Text("OAuth système · PKCE · Trousseau macOS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .background(Color.black)
        .navigationTitle("Comptes Gmail")
        .confirmationDialog(
            "Retirer ce compte ?",
            isPresented: Binding(
                get: { accountToRemove != nil },
                set: { if !$0 { accountToRemove = nil } }
            )
        ) {
            Button("Révoquer et supprimer", role: .destructive) {
                if let accountToRemove {
                    Task { await model.removeAccount(accountToRemove, revoke: true) }
                }
            }
            Button("Supprimer localement", role: .destructive) {
                if let accountToRemove {
                    Task { await model.removeAccount(accountToRemove, revoke: false) }
                }
            }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(item: $authorizationDisclosure) { purpose in
            GoogleAuthorizationDisclosure(purpose: purpose) {
                if purpose == .gmail {
                    Task { await model.addGoogleAccount() }
                }
            }
        }
    }

    private func scopeSummary(_ account: GmailAccountSummary) -> String {
        let hasSend = account.grantedScopes.contains(
            "https://www.googleapis.com/auth/gmail.send"
        )
        return hasSend
            ? model.localizedString("Autorisation d’envoi accordée")
            : model.localizedString("Autorisation d’envoi manquante")
    }
}
