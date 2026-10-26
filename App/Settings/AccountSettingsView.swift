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
                            "Default",
                            isOn: Binding(
                                get: { account.isDefault },
                                set: { enabled in
                                    if enabled { model.setDefaultAccount(account.id) }
                                }
                            )
                        )
                        .toggleStyle(.checkbox)
                        Button("Reconnect") {
                            authorizationDisclosure = .gmail
                        }
                        Button("Delete", role: .destructive) {
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
                        "No Gmail account",
                        systemImage: "envelope.badge",
                        description: Text("An account is only required when sending.")
                    )
                }
            }
            Divider()
            HStack {
                Button {
                    authorizationDisclosure = .gmail
                } label: {
                    Label("Add an account", systemImage: "plus")
                }
                Spacer()
                Text("System OAuth · PKCE · macOS Keychain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .background(Color.black)
        .navigationTitle(model.localizedString("Gmail accounts"))
        .confirmationDialog(
            "Remove This Account?",
            isPresented: Binding(
                get: { accountToRemove != nil },
                set: { if !$0 { accountToRemove = nil } }
            )
        ) {
            Button("Revoke and Remove", role: .destructive) {
                if let accountToRemove {
                    Task { await model.removeAccount(accountToRemove, revoke: true) }
                }
            }
            Button("Remove Locally", role: .destructive) {
                if let accountToRemove {
                    Task { await model.removeAccount(accountToRemove, revoke: false) }
                }
            }
            Button("Cancel", role: .cancel) {}
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
            ? model.localizedString("Send Permission Granted")
            : model.localizedString("Send Permission Missing")
    }
}
