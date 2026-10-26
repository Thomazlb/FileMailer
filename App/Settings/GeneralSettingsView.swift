import FileMailerCore
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var isDraftDeletionConfirmationPresented = false

    var body: some View {
        Form {
            Section("Language") {
                Picker(
                    "Application language",
                    selection: Binding(
                        get: { model.appLanguage },
                        set: model.saveAppLanguage
                    )
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        if language == .system {
                            Text("System language").tag(language)
                        } else {
                            Text(language.displayName).tag(language)
                        }
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("app-language-picker")
                Text("By default, FileMailer follows the macOS language.")
                    .font(.caption)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }

            Section("Finder") {
                LabeledContent("Visible recipients") {
                    Picker(
                        "Visible recipients",
                        selection: Binding(
                            get: { model.visibleRecipientCount },
                            set: model.saveVisibleCount
                        )
                    ) {
                        ForEach(1...10, id: \.self) { count in
                            Text(count, format: .number).tag(count)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 72)
                }
                Text("Pinned recipients count toward this limit.")
                    .font(.caption)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                Button("Manage the Finder extension…") {
                    model.windows?.showExtensionManagement()
                }
            }

            Section("Startup") {
                Toggle(
                    "Open FileMailer at login",
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { value in
                            Task { await model.setLaunchAtLogin(value) }
                        }
                    )
                )
                Text(model.localization.format("System Status: %@", loginStatus))
                    .font(.caption)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }

            Section("Drafts") {
                Toggle(
                    "Save drafts locally",
                    isOn: Binding(
                        get: { model.autosaveDrafts },
                        set: model.saveAutosaveDrafts
                    )
                )
                Text("Disabled by default. Attached files are never copied to a draft.")
                    .font(.caption)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                if !model.pendingDrafts.isEmpty {
                    Button("Clear saved drafts", role: .destructive) {
                        isDraftDeletionConfirmationPresented = true
                    }
                }
            }

            Section(LocalizedStringKey(usesAppleIntelligence ? "Apple Intelligence" : "Local draft")) {
                LabeledContent("Processing") {
                    Text(aiStatus)
                }
                Text("Deterministic drafting and manual writing remain available.")
                    .font(.caption)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
        .background(Color.black)
        .navigationTitle(model.localizedString("General"))
        .confirmationDialog(
            "Clear all saved drafts?",
            isPresented: $isDraftDeletionConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear drafts", role: .destructive) {
                model.clearPendingDrafts()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recipients, subjects, and bodies of these drafts will be deleted from this Mac.")
        }
    }

    private var loginStatus: String {
        switch SMAppService.mainApp.status {
        case .enabled: model.localizedString("enabled")
        case .requiresApproval: model.localizedString("approval required")
        case .notFound: model.localizedString("unavailable")
        case .notRegistered: model.localizedString("disabled")
        @unknown default: model.localizedString("unknown")
        }
    }

    private var aiStatus: String {
        switch FoundationModelAvailability.current {
        case .available: model.localizedString("On Device")
        case .unsupportedSystemVersion: model.localizedString("Deterministic draft on macOS 26")
        case .deviceNotEligible: model.localizedString("Device Not Eligible")
        case .appleIntelligenceDisabled: model.localizedString("Disabled")
        case .modelNotReady: model.localizedString("Model Not Ready")
        }
    }

    private var usesAppleIntelligence: Bool {
        FoundationModelAvailability.current == .available
    }
}
