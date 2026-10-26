import SwiftUI

enum GoogleAuthorizationPurpose: String, Identifiable {
    case gmail
    case drive
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .gmail: "Before connecting Google"
        case .drive: "Before authorizing Google Drive"
        }
    }

    var disclosure: LocalizedStringKey {
        switch self {
        case .gmail:
            "FileMailer will request your Google name and email address, plus permission to send only the messages you review and choose to send. FileMailer does not read your inbox, existing Gmail messages, or Gmail drafts. Message content and attachments are sent to Gmail only after you explicitly select Send."
        case .drive:
            "FileMailer will request access only to the files it creates or that you select with FileMailer. When you choose a Drive link, the selected file is imported into your Google Drive and accessible only to the To, Cc, and Bcc recipients of the message. FileMailer does not create a public link or request access to your entire Drive."
        }
    }
}

struct GoogleAuthorizationDisclosure: View {
    let purpose: GoogleAuthorizationPurpose
    let onContinue: @MainActor () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hasAcknowledged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(purpose.title, systemImage: "hand.raised.fill")
                .font(.title2.weight(.semibold))
            Text(purpose.disclosure)
                .fixedSize(horizontal: false, vertical: true)
            Text("OAuth tokens are stored in the macOS Keychain. FileMailer operates no server, analytics service, or third-party crash reporter.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Read the privacy policy", destination: AppConfiguration.privacyPolicyURL)
            Toggle("I have read this information and want to continue with Google.", isOn: $hasAcknowledged)
                .toggleStyle(.checkbox)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Continue with Google") {
                    dismiss()
                    Task { @MainActor in
                        await Task.yield()
                        onContinue()
                    }
                }
                .disabled(!hasAcknowledged)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(Color.black)
    }
}
