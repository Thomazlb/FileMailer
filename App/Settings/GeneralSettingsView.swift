import FileMailerCore
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var isDraftDeletionConfirmationPresented = false

    var body: some View {
        Form {
            Section("Langue") {
                Picker(
                    "Langue de l’application",
                    selection: Binding(
                        get: { model.appLanguage },
                        set: model.saveAppLanguage
                    )
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        if language == .system {
                            Text("Langue du système").tag(language)
                        } else {
                            Text(language.displayName).tag(language)
                        }
                    }
                }
                .pickerStyle(.menu)
                Text("Par défaut, FileMailer suit la langue de macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Finder") {
                LabeledContent("Destinataires visibles") {
                    Picker(
                        "Destinataires visibles",
                        selection: Binding(
                            get: { model.visibleRecipientCount },
                            set: model.saveVisibleCount
                        )
                    ) {
                        ForEach(1...10, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 72)
                }
                Text("Les destinataires épinglés comptent dans cette limite.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Gérer l’extension Finder…") {
                    model.windows?.showExtensionManagement()
                }
            }

            Section("Démarrage") {
                Toggle(
                    "Ouvrir FileMailer à la connexion",
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { value in
                            Task { await model.setLaunchAtLogin(value) }
                        }
                    )
                )
                Text("État système: \(loginStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Brouillons") {
                Toggle(
                    "Enregistrer les brouillons localement",
                    isOn: Binding(
                        get: { model.autosaveDrafts },
                        set: model.saveAutosaveDrafts
                    )
                )
                Text("Désactivé par défaut. Les fichiers joints ne sont jamais copiés dans un brouillon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.pendingDrafts.isEmpty {
                    Button("Effacer les brouillons enregistrés", role: .destructive) {
                        isDraftDeletionConfirmationPresented = true
                    }
                }
            }

            Section(usesAppleIntelligence ? "Intelligence Apple" : "Brouillon local") {
                LabeledContent("Traitement") {
                    Text(aiStatus)
                }
                if usesAppleIntelligence {
                    LabeledContent("Extension Golden Gate") {
                        Text("Compilée")
                    }
                }
                Text("Le brouillon déterministe et la rédaction manuelle restent disponibles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
        .background(Color.black)
        .navigationTitle("Général")
        .confirmationDialog(
            "Effacer tous les brouillons enregistrés ?",
            isPresented: $isDraftDeletionConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Effacer les brouillons", role: .destructive) {
                model.clearPendingDrafts()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les destinataires, objets et corps de ces brouillons seront supprimés de ce Mac.")
        }
    }

    private var loginStatus: String {
        switch SMAppService.mainApp.status {
        case .enabled: model.localizedString("activé")
        case .requiresApproval: model.localizedString("autorisation requise")
        case .notFound: model.localizedString("indisponible")
        case .notRegistered: model.localizedString("désactivé")
        @unknown default: model.localizedString("inconnu")
        }
    }

    private var aiStatus: String {
        switch FoundationModelAvailability.current {
        case .available: model.localizedString("Sur l’appareil")
        case .unsupportedSystemVersion: model.localizedString("Brouillon déterministe sur macOS 26")
        case .deviceNotEligible: model.localizedString("Appareil non éligible")
        case .appleIntelligenceDisabled: model.localizedString("Désactivé")
        case .modelNotReady: model.localizedString("Modèle pas encore prêt")
        }
    }

    private var usesAppleIntelligence: Bool {
        FoundationModelAvailability.current == .available
    }
}
