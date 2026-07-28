import AppKit
import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    @State private var copied = false

    var body: some View {
        Form {
            Section("Extension Finder") {
                LabeledContent("Heartbeat") {
                    Text(model.lastExtensionHeartbeat?.formatted() ?? "Absent")
                }
                LabeledContent("Dernier snapshot") {
                    Text(model.lastSnapshotDate?.formatted() ?? "Absent")
                }
                LabeledContent("Schéma IPC") {
                    Text("1")
                }
                Button("Ouvrir les réglages d’extensions…") {
                    model.windows?.showExtensionManagement()
                }
                Text("Si le menu n’apparaît pas, activez FileMailer dans Réglages Système > Général > Ouverture et extensions > Extensions du Finder, puis rouvrez le menu contextuel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Rapport nettoyé") {
                ScrollView {
                    Text(model.diagnosticReport())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 220)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.diagnosticReport(), forType: .string)
                    copied = true
                } label: {
                    Text(LocalizedStringKey(copied ? "Copié" : "Copier le rapport"))
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
        .background(Color.black)
        .navigationTitle("Diagnostic")
    }
}
