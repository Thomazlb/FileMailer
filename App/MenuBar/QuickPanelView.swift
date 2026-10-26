import FileMailerCore
import SwiftUI

struct QuickPanelView: View {
    @ObservedObject var model: AppModel

    private var topRecipients: [RecipientProfile] {
        DefaultRecipientRanker().ranked(
            recipients: model.recipients,
            excludingOwnAddresses: [],
            limit: 5,
            now: Date()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppConfiguration.appName)
                        .font(.headline)
                    Text(defaultAccountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.windows?.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text("In Finder, right-click a file, choose Send by Email, then choose a recipient.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)

            VStack(alignment: .leading, spacing: 6) {
                Text("Finder Menu Recipients")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if topRecipients.isEmpty {
                    Text("No registered recipient")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(topRecipients) { recipient in
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(.secondary)
                        Text(recipient.displayName.isEmpty ? recipient.email : recipient.displayName)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                Label(modelStatus, systemImage: modelStatusSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Extension") {
                    model.windows?.showSettings(section: .diagnostics)
                }
                .buttonStyle(.link)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, model.interfaceLocale)
        .environment(\.layoutDirection, model.interfaceLocale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
    }

    private var defaultAccountText: String {
        let account = model.accounts.first(where: \.isDefault) ?? model.accounts.first
        return account?.email ?? model.localizedString("No Gmail account")
    }

    private var modelStatus: String {
        switch FoundationModelAvailability.current {
        case .available: model.localizedString("Apple Intelligence available")
        case .unsupportedSystemVersion: model.localizedString("Deterministic draft on macOS 26")
        case .deviceNotEligible: model.localizedString("Deterministic draft")
        case .appleIntelligenceDisabled: model.localizedString("Apple Intelligence disabled")
        case .modelNotReady: model.localizedString("Model Preparing")
        }
    }

    private var modelStatusSymbol: String {
        FoundationModelAvailability.current == .available ? "apple.intelligence" : "text.badge.checkmark"
    }
}

struct MenuBarPanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        QuickPanelView(model: model)
            .padding(.top, 10)
            .background {
                MenuBarPanelShape()
                    .fill(Color.black)
                    .overlay {
                        MenuBarPanelShape()
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .fixedSize()
    }
}

private struct MenuBarPanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        let arrowHeight: CGFloat = 10
        let arrowHalfWidth: CGFloat = 12
        let radius: CGFloat = 20
        let top = rect.minY + arrowHeight
        let centerX = rect.midX
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + radius, y: top))
        path.addLine(to: CGPoint(x: centerX - arrowHalfWidth, y: top))
        path.addLine(to: CGPoint(x: centerX, y: rect.minY))
        path.addLine(to: CGPoint(x: centerX + arrowHalfWidth, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: top + radius),
            control: CGPoint(x: rect.maxX, y: top)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: top + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: top),
            control: CGPoint(x: rect.minX, y: top)
        )
        path.closeSubpath()
        return path
    }
}
