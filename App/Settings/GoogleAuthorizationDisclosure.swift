import SwiftUI

enum GoogleAuthorizationPurpose: String, Identifiable {
    case gmail
    case drive
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .gmail: "Avant de connecter Google"
        case .drive: "Avant d’autoriser Google Drive"
        }
    }

    var disclosure: LocalizedStringKey {
        switch self {
        case .gmail:
            "FileMailer demandera votre nom et votre adresse e-mail Google, ainsi que l’autorisation d’envoyer les messages que vous avez relus et choisi d’envoyer. FileMailer ne lit pas votre boîte de réception, vos messages existants ni vos brouillons Gmail. Le contenu du message et ses pièces jointes ne sont transmis à Gmail qu’après votre action explicite sur Envoyer."
        case .drive:
            "FileMailer demandera l’accès uniquement aux fichiers qu’il crée ou que vous sélectionnez avec FileMailer. Lorsque vous choisissez un lien Drive, le fichier sélectionné est importé dans votre Google Drive et accessible seulement aux destinataires À, Cc et Cci du message. FileMailer ne crée pas de lien public et ne demande pas l’accès à l’ensemble de votre Drive."
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
            Text("Les jetons OAuth sont stockés dans le Trousseau macOS. FileMailer n’exploite aucun serveur, service d’analyse ou rapporteur de crash tiers.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Lire la politique de confidentialité", destination: AppConfiguration.privacyPolicyURL)
            Toggle("J’ai lu ces informations et je souhaite continuer avec Google.", isOn: $hasAcknowledged)
                .toggleStyle(.checkbox)
            HStack {
                Button("Annuler", role: .cancel) { dismiss() }
                Spacer()
                Button("Continuer avec Google") {
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
