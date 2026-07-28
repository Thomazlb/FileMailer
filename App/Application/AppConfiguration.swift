import Foundation

enum AppConfiguration {
    static let homepageURL = URL(string: "https://filemail.online/")!
    static let privacyPolicyURL = URL(string: "https://filemail.online/privacy/")!

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "FileMailer"
    }

    static var baseBundleID: String {
        Bundle.main.object(forInfoDictionaryKey: "FileMailerBaseBundleID") as? String
            ?? Bundle.main.bundleIdentifier
            ?? "org.filemailer.FileMailer"
    }

    static var googleClientID: String {
        Bundle.main.object(forInfoDictionaryKey: "FileMailerGoogleClientID") as? String ?? ""
    }

    static var googleRedirectScheme: String {
        Bundle.main.object(
            forInfoDictionaryKey: "FileMailerGoogleRedirectScheme"
        ) as? String ?? ""
    }

    static var goldenGateFeaturesEnabled: Bool {
        let raw = Bundle.main.object(
            forInfoDictionaryKey: "FileMailerGoldenGateFeatures"
        ) as? String
        return raw == "YES"
    }
}
