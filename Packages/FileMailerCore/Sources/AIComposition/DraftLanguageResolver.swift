import FileMailerDomain
import Foundation

public enum DraftLanguageResolver {
    /// Only trusted writing instructions can override the selected language.
    /// File names, document excerpts and recipient identities never take part.
    public static func resolve(_ request: DraftGenerationRequest) -> String {
        for instruction in [request.userPurpose, request.customInstruction] {
            if let instruction, let language = explicitLanguage(in: instruction) { return language }
        }
        return request.language.localeIdentifier
            ?? FileMailerLocalization(languageIdentifier: request.appLanguageIdentifier).languageIdentifier
    }

    public static func explicitLanguage(in instruction: String) -> String? {
        let text = instruction.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                       locale: Locale(identifier: "en_US_POSIX"))
        let action = #"(?:ecri\w*|redig\w*|repond\w*|tradui\w*|tradu\w*|write|writing|written|rewrite|reply|respond|compose|translate|schreib\w*|verfass\w*|antwort\w*|ubersetz\w*|escrib\w*|redact\w*|respon\w*|scriv\w*|rispond\w*|schrijf\w*|courriel|e-mail|email|mail|message|objet|corps)"#
        let marker = #"(?:en|in|into|to|auf|em|на|ب)\s+"#
        var result: (Int, String)?
        for identifier in FileMailerLocalization.supportedIdentifiers {
            var names = Set<String>()
            for displayLocale in ["en", "fr", "de", "es", "pt", "it", "nl", identifier] {
                let locale = Locale(identifier: displayLocale)
                if let name = locale.localizedString(forIdentifier: identifier) {
                    names.insert(name)
                }
                if (!identifier.contains("-") || identifier == "pt-PT" || identifier == "zh-Hans"),
                   let code = Locale(identifier: identifier).language.languageCode?.identifier,
                   let name = locale.localizedString(forLanguageCode: code) { names.insert(name) }
            }
            for name in names {
                let normalized = name.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                              locale: Locale(identifier: "en_US_POSIX"))
                if text.trimmingCharacters(in: .whitespacesAndNewlines) == normalized { return identifier }
                let languageName = NSRegularExpression.escapedPattern(for: normalized) + #"\b"#
                let pattern = #"(?:^\s*"# + marker + languageName
                    + #"|\b(?:langue|language|idioma)\s*[:=]\s*(?:"# + marker + #")?"# + languageName
                    + #"|\b"# + action + #"\b[^\n.!?;]{0,100}?\b"# + marker + languageName + ")"
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let range = Range(match.range, in: text) else { continue }
                    let clause = text[..<range.upperBound]
                        .components(separatedBy: CharacterSet(charactersIn: ".!?;\n")).last ?? ""
                    // A prohibition is not a request to use that language.
                    if clause.range(of: #"\b(?:pas|jamais|not|never|nicht|nao|non)\b|\bdon['’]t\b"#,
                                    options: .regularExpression) != nil { continue }
                    let end = NSMaxRange(match.range)
                    if result == nil || end > result!.0 {
                        result = (end, identifier)
                    }
                }
            }
        }
        return result?.1
    }
}
