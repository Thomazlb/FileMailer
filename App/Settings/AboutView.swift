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
            Text("Send files from Finder with full verification before each send.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text("Open source project under MIT license. No analytics, tracking or intermediate server.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link("Privacy Policy", destination: AppConfiguration.privacyPolicyURL)
                .font(.caption)
            Button("Review onboarding") {
                model.windows?.showOnboarding()
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .navigationTitle(model.localizedString("About"))
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
