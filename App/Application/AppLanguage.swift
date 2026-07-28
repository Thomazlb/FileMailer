import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case arabic = "ar"
    case bangla = "bn"
    case catalan = "ca"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case croatian = "hr"
    case czech = "cs"
    case danish = "da"
    case dutch = "nl"
    case englishAustralia = "en-AU"
    case englishCanada = "en-CA"
    case englishUnitedKingdom = "en-GB"
    case englishUnitedStates = "en"
    case finnish = "fi"
    case french = "fr"
    case frenchCanada = "fr-CA"
    case german = "de"
    case greek = "el"
    case gujarati = "gu"
    case hebrew = "he"
    case hindi = "hi"
    case hungarian = "hu"
    case indonesian = "id"
    case italian = "it"
    case japanese = "ja"
    case kannada = "kn"
    case korean = "ko"
    case malay = "ms"
    case malayalam = "ml"
    case marathi = "mr"
    case norwegian = "no"
    case odia = "or"
    case polish = "pl"
    case portugueseBrazil = "pt-BR"
    case portuguesePortugal = "pt-PT"
    case punjabi = "pa"
    case romanian = "ro"
    case russian = "ru"
    case slovak = "sk"
    case slovenian = "sl"
    case spanishMexico = "es-MX"
    case spanishSpain = "es"
    case swedish = "sv"
    case tamil = "ta"
    case telugu = "te"
    case thai = "th"
    case turkish = "tr"
    case ukrainian = "uk"
    case urdu = "ur"
    case vietnamese = "vi"

    var id: String { rawValue }

    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    var resourceIdentifier: String {
        self == .norwegian ? "nb" : rawValue
    }

    var displayName: String {
        guard self != .system else { return "" }
        let nativeLocale = Locale(identifier: rawValue)
        return nativeLocale.localizedString(forIdentifier: rawValue)?
            .capitalized(with: nativeLocale)
            ?? rawValue
    }
}
