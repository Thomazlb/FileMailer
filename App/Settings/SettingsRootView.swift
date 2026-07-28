import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var model: AppModel
    @State private var selection: WindowCoordinator.SettingsSection

    init(model: AppModel, initialSection: WindowCoordinator.SettingsSection) {
        self.model = model
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        HStack(spacing: 0) {
            List(WindowCoordinator.SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .frame(width: 190)

            Divider()

            Group {
                switch selection {
                case .general:
                    GeneralSettingsView(model: model)
                case .recipients:
                    RecipientSettingsView(model: model)
                case .accounts:
                    AccountSettingsView(model: model)
                case .diagnostics:
                    DiagnosticsView(model: model)
                case .about:
                    AboutView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Color.black)
        .environment(\.locale, model.interfaceLocale)
    }
}

private extension WindowCoordinator.SettingsSection {
    var title: LocalizedStringKey {
        switch self {
        case .general: "Général"
        case .recipients: "Destinataires"
        case .accounts: "Comptes Gmail"
        case .diagnostics: "Diagnostic"
        case .about: "À propos"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .recipients: "person.2"
        case .accounts: "envelope"
        case .diagnostics: "stethoscope"
        case .about: "info.circle"
        }
    }
}
