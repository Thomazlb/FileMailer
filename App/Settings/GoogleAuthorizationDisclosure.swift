import SwiftUI

enum GoogleAuthorizationPurpose: String, Identifiable {
    case gmail
    case drive

    var id: String { rawValue }

    func title(inFrench: Bool) -> String {
        if inFrench {
            switch self {
            case .gmail:
                return "Avant de connecter Google"
            case .drive:
                return "Avant d’autoriser Google Drive"
            }
        }
        switch self {
        case .gmail:
            return "Before connecting Google"
        case .drive:
            return "Before authorizing Google Drive"
        }
    }

    func disclosure(inFrench: Bool) -> String {
        if inFrench {
            switch self {
            case .gmail:
                return "FileMailer demandera votre nom et votre adresse e-mail Google, ainsi que l’autorisation d’envoyer les messages que vous avez relus et choisi d’envoyer. FileMailer ne lit pas votre boîte de réception, vos messages existants ni vos brouillons Gmail. Le contenu du message et ses pièces jointes ne sont transmis à Gmail qu’après votre action explicite sur Envoyer."
            case .drive:
                return "FileMailer demandera l’accès uniquement aux fichiers qu’il crée ou que vous sélectionnez avec FileMailer. Lorsque vous choisissez un lien Drive, le fichier sélectionné est importé dans votre Google Drive et accessible seulement aux destinataires To, Cc et Cci du message. FileMailer ne crée pas de lien public et ne demande pas l’accès à l’ensemble de votre Drive."
            }
        }
        switch self {
        case .gmail:
            return "FileMailer will request your Google name and email address, plus permission to send only the messages you review and choose to send. FileMailer does not read your inbox, existing Gmail messages, or Gmail drafts. Message content and attachments are sent to Gmail only after you explicitly select Send."
        case .drive:
            return "FileMailer will request access only to files it creates or that you select with FileMailer. When you choose Drive delivery, the selected file is uploaded to your Google Drive and available only to the message’s To, Cc, and Bcc recipients. FileMailer does not create a public link or request access to your entire Drive."
        }
    }
}

struct GoogleAuthorizationDisclosure: View {
    let purpose: GoogleAuthorizationPurpose
    let onContinue: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var hasAcknowledged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(purpose.title(inFrench: displaysFrench), systemImage: "hand.raised.fill")
                .font(.title2.weight(.semibold))

            Text(purpose.disclosure(inFrench: displaysFrench))
                .fixedSize(horizontal: false, vertical: true)

            Text(protectionDisclosure)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Link(
                displaysFrench ? "Lire la politique de confidentialité" : "Read the Privacy Policy",
                destination: AppConfiguration.privacyPolicyURL
            )

            Toggle(
                displaysFrench
                    ? "J’ai lu ces informations et je souhaite continuer avec Google."
                    : "I have read this information and want to continue with Google.",
                isOn: $hasAcknowledged
            )
            .toggleStyle(.checkbox)

            HStack {
                Button(displaysFrench ? "Annuler" : "Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button(displaysFrench ? "Continuer avec Google" : "Continue with Google") {
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

    private var displaysFrench: Bool {
        locale.identifier.lowercased().hasPrefix("fr")
    }

    private var protectionDisclosure: String {
        if displaysFrench {
            "Les jetons OAuth sont stockés dans le Trousseau macOS. "
                + "FileMailer n’exploite aucun serveur, analytics ou rapporteur de crash tiers."
        } else {
            "OAuth tokens are stored in the macOS Keychain. "
                + "FileMailer operates no server, analytics service, or third-party crash reporter."
        }
    }
}
