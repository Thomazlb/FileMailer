import AppKit
import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    @State private var copied = false

    var body: some View {
        Form {
            Section("Finder Extension") {
                LabeledContent("Presence signal") {
                    Text(model.lastExtensionHeartbeat?.formatted(.dateTime.locale(model.interfaceLocale)) ?? model.localizedString("Absent"))
                }
                LabeledContent("Latest Snapshot") {
                    Text(model.lastSnapshotDate?.formatted(.dateTime.locale(model.interfaceLocale)) ?? model.localizedString("Absent"))
                }
                LabeledContent("IPC Schema") {
                    Text("1")
                }
                Button("Open extension settings…") {
                    model.windows?.showExtensionManagement()
                }
                Text("If the menu does not appear, enable FileMailer in System Settings > General > Login Items & Extensions > Finder Extensions, then reopen the context menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sanitised Report") {
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
                    Text(LocalizedStringKey(copied ? "Copied" : "Copy Report"))
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
        .background(Color.black)
        .navigationTitle(model.localizedString("Diagnostics"))
    }
}
