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
                        title: "Welcome to FileMailer",
                        text: "An open source macOS app for preparing and reviewing every message sent from Finder."
                    )
                case 1:
                    page(
                        symbol: "hand.raised",
                        title: "Local by Default",
                        text: "Analysis and Apple Intelligence generation stay on your Mac. The message and its attachments go to Google only when you press Send."
                    )
                case 2:
                    actionPage(
                        symbol: "puzzlepiece.extension",
                        title: "Enable the Finder Extension",
                        text: "macOS requires manual activation. FileMailer does not inject code into Finder.",
                        actionTitle: "Open extension settings"
                    ) {
                        model.windows?.showExtensionManagement()
                    }
                case 3:
                    actionPage(
                        symbol: "envelope.badge",
                        title: "Add a Gmail Account",
                        text: model.accounts.isEmpty
                            ? "The system browser will open with only the permissions required to send."
                            : model.localization.format("%@ connected account(s).", String(model.accounts.count)),
                        actionTitle: "Add an account"
                    ) {
                        authorizationDisclosure = .gmail
                    }
                case 4:
                    actionPage(
                        symbol: "person.2",
                        title: "Add Your Recipients",
                        text: "Pin your main contacts and choose their order in the Finder menu.",
                        actionTitle: "Manage Recipients"
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
                        title: "Open at Login",
                        text: model.launchAtLogin
                            ? "FileMailer is configured to open at login."
                            : "This option is optional and can be changed in Settings.",
                        actionTitle: model.launchAtLogin ? "Disable" : "Enable"
                    ) {
                        Task { await model.setLaunchAtLogin(!model.launchAtLogin) }
                    }
                default:
                    actionPage(
                        symbol: "doc.badge.plus",
                        title: "Try a Non-Sensitive File",
                        text: "Choose a test file. A compose window will open without ever sending automatically.",
                        actionTitle: "Choose a file…"
                    ) {
                        model.openFilesCompose()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Previous") { step = max(0, step - 1) }
                    .disabled(step == 0)
                Spacer()
                Button(LocalizedStringKey(step == stepCount - 1 ? "Finish" : "Continue")) {
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
        .environment(\.layoutDirection, model.interfaceLocale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
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
            Text(model.localizedString(text))
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
            "The Foundation Models model is available on this device."
        case .unsupportedSystemVersion:
            "On macOS 26, FileMailer offers deterministic drafting and manual drafting. Apple Intelligence is reserved for macOS 27 or later."
        case .deviceNotEligible:
            "This device is not eligible. The deterministic draft and manual writing remain available."
        case .appleIntelligenceDisabled:
            "Apple Intelligence is disabled. You can enable it later in System Settings."
        case .modelNotReady:
            "The model is preparing. FileMailer will use its deterministic fallback in the meantime."
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
            : "Local draft"
    }
}
