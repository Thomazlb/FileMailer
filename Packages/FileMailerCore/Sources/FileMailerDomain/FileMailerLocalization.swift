import Foundation

/// A value-based language resolver shared by the app, services and Finder extension.
/// Looking up a string never depends on the language cached by Bundle.main at launch.
public struct FileMailerLocalization: Sendable {
    public static let supportedIdentifiers = [
        "ar", "bn", "ca", "zh-Hans", "zh-Hant", "hr", "cs", "da", "nl",
        "en-AU", "en-CA", "en-GB", "en", "fi", "fr", "fr-CA", "de", "el",
        "gu", "he", "hi", "hu", "id", "it", "ja", "kn", "ko", "ms", "ml",
        "mr", "no", "or", "pl", "pt-BR", "pt-PT", "pa", "ro", "ru", "sk",
        "sl", "es-MX", "es", "sv", "ta", "te", "th", "tr", "uk", "ur", "vi"
    ]

    public let languageIdentifier: String
    public var locale: Locale { Locale(identifier: languageIdentifier) }

    public init(languageIdentifier: String) {
        self.languageIdentifier = Self.resolve(preferences: [languageIdentifier])
    }

    public static var current: Self {
        let selected = UserDefaults.standard.string(forKey: "appLanguage")
        return Self(languageIdentifier: selected.flatMap { $0 == "system" ? nil : $0 }
            ?? resolve(preferences: Locale.preferredLanguages))
    }

    public static func resolve(preferences: [String]) -> String {
        for preference in preferences {
            let identifier = preference.replacingOccurrences(of: "_", with: "-")
            if supportedIdentifiers.contains(identifier) { return identifier }
            if identifier == "nb" || identifier.hasPrefix("nb-") { return "no" }
            if identifier.hasPrefix("zh") {
                return identifier.contains("Hant") || identifier.contains("TW")
                    || identifier.contains("HK") || identifier.contains("MO") ? "zh-Hant" : "zh-Hans"
            }
            let base = identifier.components(separatedBy: "-")[0]
            if supportedIdentifiers.contains(base) { return base }
            if base == "pt" { return "pt-PT" }
        }
        return "en"
    }

    public func string(_ key: String, bundle: Bundle = .main) -> String {
        for candidate in [bundle, Bundle.module] {
            // Foundation may compile Norwegian resources as either no or nb.
            let identifiers = languageIdentifier == "no" ? ["no", "nb"] : [languageIdentifier]
            for identifier in identifiers {
                guard let path = candidate.path(forResource: identifier, ofType: "lproj"),
                      let localizedBundle = Bundle(path: path)
                else { continue }
                let missing = "\u{1f}FileMailerMissingTranslation\u{1f}"
                let value = localizedBundle.localizedString(forKey: key, value: missing, table: nil)
                if value != missing { return value }
            }
        }
        return key
    }

    public func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }
}
