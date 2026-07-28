import FileMailerCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    let onFinish: () -> Void
    @State private var step = 0
    @State private var authorizationDisclosure: GoogleAuthorizationPurpose?

    private let stepCount = 8

    var body: some View {
        VStack(spacing: 22) {
            ProgressView(value: Double(step + 1), total: Double(stepCount))
            Group {
                switch step {
                case 0:
                    page(
                        symbol: "paperplane.circle",
                        title: "Bienvenue dans FileMailer",
                        text: "Une application macOS open source pour préparer et relire chaque envoi depuis le Finder."
                    )
                case 1:
                    page(
                        symbol: "hand.raised",
                        title: "Local par défaut",
                        text: "L’analyse et la génération Apple Intelligence restent sur votre Mac. Le message et ses pièces jointes vont uniquement chez Google au moment où vous appuyez sur Envoyer."
                    )
                case 2:
                    actionPage(
                        symbol: "puzzlepiece.extension",
                        title: "Activez l’extension Finder",
                        text: "macOS exige une activation manuelle. FileMailer n’injecte aucun code dans le Finder.",
                        actionTitle: "Ouvrir les réglages d’extensions"
                    ) {
                        model.windows?.showExtensionManagement()
                    }
                case 3:
                    actionPage(
                        symbol: "envelope.badge",
                        title: "Ajoutez un compte Gmail",
                        text: model.accounts.isEmpty
                            ? "Le navigateur système s’ouvrira avec les seules autorisations nécessaires à l’envoi."
                            : "\(model.accounts.count) compte(s) connecté(s).",
                        actionTitle: "Ajouter un compte"
                    ) {
                        authorizationDisclosure = .gmail
                    }
                case 4:
                    actionPage(
                        symbol: "person.2",
                        title: "Ajoutez vos destinataires",
                        text: "Épinglez vos contacts principaux et choisissez leur ordre dans le menu Finder.",
                        actionTitle: "Gérer les destinataires"
                    ) {
                        model.windows?.showSettings(section: .recipients)
                    }
                case 5:
                    page(
                        symbol: aiSymbol,
                        title: aiTitle,
                        text: aiExplanation
                    )
                case 6:
                    actionPage(
                        symbol: "power",
                        title: "Lancement à la connexion",
                        text: model.launchAtLogin
                            ? "FileMailer est configuré pour démarrer à la connexion."
                            : "Ce choix reste facultatif et modifiable dans les réglages.",
                        actionTitle: model.launchAtLogin ? "Désactiver" : "Activer"
                    ) {
                        Task { await model.setLaunchAtLogin(!model.launchAtLogin) }
                    }
                default:
                    actionPage(
                        symbol: "doc.badge.plus",
                        title: "Essayez avec un fichier non sensible",
                        text: "Choisissez un fichier de test. Une fenêtre de composition s’ouvrira, sans jamais envoyer automatiquement.",
                        actionTitle: "Choisir un fichier…"
                    ) {
                        model.openFilesCompose()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Précédent") { step = max(0, step - 1) }
                    .disabled(step == 0)
                Spacer()
                Button(step == stepCount - 1 ? "Terminer" : "Continuer") {
                    if step == stepCount - 1 {
                        onFinish()
                    } else {
                        step += 1
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 700, height: 520)
        .background(Color.black)
        .environment(\.locale, model.interfaceLocale)
        .sheet(item: $authorizationDisclosure) { purpose in
            GoogleAuthorizationDisclosure(purpose: purpose) {
                if purpose == .gmail {
                    Task { await model.addGoogleAccount() }
                }
            }
        }
    }

    private func page(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(LocalizedStringKey(title))
                .font(.largeTitle.weight(.semibold))
            Text(LocalizedStringKey(text))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 500)
        }
    }

    private func actionPage(
        symbol: String,
        title: String,
        text: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 18) {
            page(symbol: symbol, title: title, text: text)
            Button(action: action) {
                Text(LocalizedStringKey(actionTitle))
            }
        }
    }

    private var aiExplanation: String {
        switch FoundationModelAvailability.current {
        case .available:
            "Le modèle Foundation Models est disponible sur cet appareil."
        case .unsupportedSystemVersion:
            "Sur macOS 26, FileMailer propose un brouillon déterministe et la rédaction manuelle. Apple Intelligence est réservé à macOS 27 ou ultérieur."
        case .deviceNotEligible:
            "Cet appareil n’est pas éligible. Le brouillon déterministe et la rédaction manuelle restent disponibles."
        case .appleIntelligenceDisabled:
            "Apple Intelligence est désactivé. Vous pourrez l’activer plus tard dans Réglages Système."
        case .modelNotReady:
            "Le modèle est en préparation. FileMailer utilisera le fallback déterministe entre-temps."
        }
    }

    private var aiSymbol: String {
        FoundationModelAvailability.current == .available
            ? "apple.intelligence"
            : "text.badge.checkmark"
    }

    private var aiTitle: String {
        FoundationModelAvailability.current == .available
            ? "Apple Intelligence"
            : "Brouillon local"
    }
}
