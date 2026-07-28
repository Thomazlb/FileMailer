import SwiftUI

struct AboutView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(AppConfiguration.appName)
                .font(.largeTitle.weight(.semibold))
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("Envoyez des fichiers depuis le Finder avec une vérification complète avant chaque envoi.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text("Projet open source sous licence MIT. Aucun analytics, tracking ou serveur intermédiaire.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link("Politique de confidentialité", destination: AppConfiguration.privacyPolicyURL)
                .font(.caption)
            Button("Revoir l’onboarding") {
                model.windows?.showOnboarding()
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .navigationTitle("À propos")
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
