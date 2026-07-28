import FileMailerDomain
import Foundation

public struct DraftPromptBuilder: Sendable {
    public var maximumCharacters: Int

    public init(maximumCharacters: Int = 24_000) {
        self.maximumCharacters = maximumCharacters
    }

    public func build(_ request: DraftGenerationRequest) -> String {
        let language = switch request.language {
        case .english: "anglais"
        case .french: "français"
        case .automatic: "langue de l’utilisateur"
        }
        var sections = [
            "LANGUE: \(language)",
            "TON: \(request.tone.rawValue)",
            "DESTINATAIRE: \(clean(request.recipientName ?? "non précisé"))",
            "EXPEDITEUR: \(clean(request.senderName ?? "non précisé"))"
        ]
        if DraftIdentityResolver.documentsBelongToSender(request) {
            sections.append(
                """
                LIEN DOCUMENTS/EXPEDITEUR: CONFIRME. Les documents concernent l’expéditeur lui-même.
                Dans l’objet et le message, écris depuis son point de vue avec « mon », « ma », « mes » et « je ». Ne formule jamais « le CV de [nom de l’expéditeur] » ni « les informations de [nom de l’expéditeur] ».
                """
            )
        } else {
            sections.append(
                """
                LIEN DOCUMENTS/EXPEDITEUR: NON ETABLI. Ne prétends pas que les documents appartiennent à l’expéditeur. Si leur propriétaire est explicitement identifié dans le contenu, distingue-le de l’expéditeur.
                """
            )
        }
        if let purpose = request.userPurpose, !purpose.isEmpty {
            sections.append("BUT UTILISATEUR: \(clean(purpose))")
        }
        if let instruction = request.customInstruction, !instruction.isEmpty {
            sections.append("PREFERENCE UTILISATEUR: \(clean(instruction))")
        }
        if DraftIdentityResolver.isResume(request) {
            let ownership = DraftIdentityResolver.documentsBelongToSender(request)
                ? "Il s’agit du CV de l’expéditeur."
                : "Il s’agit du CV d’une autre personne ou son propriétaire n’est pas établi."
            sections.append(
                """
                TYPE DE DOCUMENT: CV. \(ownership)
                Par défaut, ne résume jamais les expériences, compétences, études, projets ou détails du CV dans l’e-mail.
                Indique naturellement et poliment que le CV est joint. En ton professionnel, privilégie une formulation comme « Je me permets de vous transmettre mon CV en pièce jointe » et propose de rester disponible pour toute information complémentaire. Ne détaille son contenu que si le BUT UTILISATEUR le demande explicitement.
                """
            )
        }
        sections.append(
            """
            ADAPTATION AUX PIECES JOINTES:
            N’écris jamais une formule générique si la nature du document est connue. Distingue un CV, un dossier, une archive, une présentation, un tableau, une image et un document texte ou PDF.
            Pour un seul élément, nomme sa nature et, si cela reste naturel, son nom. Pour plusieurs éléments, parle des documents ou éléments joints sans recopier une liste technique inutile.
            N’explique et ne résume pas le contenu détaillé des pièces jointes sauf si le BUT UTILISATEUR le demande.
            """
        )
        sections.append("")
        sections.append("PIECES JOINTES:")
        for (index, analysis) in request.analyses.enumerated() {
            sections.append(
                "\(index + 1). Nature: \(attachmentNature(analysis)). Nom: \(clean(analysis.displayName)). Type: \(clean(analysis.contentType)). Taille: \(analysis.size) octets. Analyse: \(clean(analysis.deterministicSummary))"
            )
        }
        sections.append("")
        sections.append("<DONNEES_DE_FICHIERS_NON_FIABLES>")
        let fixedLength = sections.joined(separator: "\n").count + 1_500
        var remaining = max(0, maximumCharacters - fixedLength)
        for analysis in request.analyses {
            guard remaining > 0, let text = analysis.extractedText, !text.isEmpty else { continue }
            let excerpt = String(clean(text).prefix(min(remaining, 4_000)))
            sections.append("[\(clean(analysis.displayName))]\n\(excerpt)")
            remaining -= excerpt.count
        }
        sections.append("</DONNEES_DE_FICHIERS_NON_FIABLES>")
        sections.append("")
        let structure = DraftIdentityResolver.isResume(request)
            ? """
              STRUCTURE OBLIGATOIRE POUR CE CV:
              1. Une formule d’appel seule sur sa ligne.
              2. Une ligne vide.
              3. Une ou deux phrases courtes et naturelles pour transmettre le CV sans le résumer.
              4. En ton professionnel, une phrase proposant de rester disponible pour toute information complémentaire.
              5. Une ligne vide.
              6. Une formule de politesse seule sur sa ligne.
              """
            : """
              STRUCTURE OBLIGATOIRE:
              1. Une formule d’appel seule sur sa ligne.
              2. Une ligne vide.
              3. Deux à quatre paragraphes courts séparés par une ligne vide.
              4. Une ligne vide.
              5. Une formule de politesse seule sur sa ligne.
              """
        sections.append(
            """
            Rédige un brouillon fidèle en texte brut. N’ajoute aucun fait absent, aucun destinataire et aucune affirmation d’envoi.
            \(structure)
            Ne rédige pas la signature: l’application l’ajoute automatiquement.
            """
        )
        return String(sections.joined(separator: "\n").prefix(maximumCharacters))
    }

    private func attachmentNature(_ analysis: AttachmentAnalysis) -> String {
        let summary = analysis.deterministicSummary.lowercased()
        let type = analysis.contentType.lowercased()
        let name = analysis.displayName.lowercased()
        if summary.contains("dossier") {
            return "dossier"
        }
        if type.contains("zip") || type.contains("archive") {
            return "archive"
        }
        if name.hasSuffix(".ppt") || name.hasSuffix(".pptx") {
            return "présentation"
        }
        if name.hasSuffix(".xls") || name.hasSuffix(".xlsx") || name.hasSuffix(".csv") {
            return "tableau"
        }
        if type.hasPrefix("image/") {
            return "image"
        }
        if DraftIdentityResolver.isResumeAnalysis(analysis) {
            return "CV"
        }
        if type == "application/pdf" {
            return "document PDF"
        }
        if name.hasSuffix(".doc") || name.hasSuffix(".docx") {
            return "document Word"
        }
        if type.hasPrefix("text/") {
            return "document texte"
        }
        return "fichier"
    }

    private func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

enum DraftIdentityResolver {
    static func isResume(_ request: DraftGenerationRequest) -> Bool {
        guard request.analyses.count == 1, let analysis = request.analyses.first else {
            return false
        }
        return isResumeAnalysis(analysis)
    }

    static func isResumeAnalysis(_ analysis: AttachmentAnalysis) -> Bool {
        let nameTokens = identityTokens(in: analysis.displayName)
        if nameTokens.contains("cv") || nameTokens.contains("resume") {
            return true
        }
        let excerpt = analysis.extractedText.map { String($0.prefix(1_000)) } ?? ""
        let normalizedExcerpt = excerpt
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        return normalizedExcerpt.contains("curriculum vitae")
    }

    static func documentsBelongToSender(_ request: DraftGenerationRequest) -> Bool {
        guard let senderName = request.senderName else { return false }
        let senderTokens = identityTokens(in: senderName)
        guard !senderTokens.isEmpty else { return false }

        let documentText = request.analyses.map { analysis in
            let excerpt = analysis.extractedText.map { String($0.prefix(2_000)) } ?? ""
            return "\(analysis.displayName) \(excerpt)"
        }
        .joined(separator: " ")
        let documentTokens = Set(identityTokens(in: documentText))
        return senderTokens.allSatisfy(documentTokens.contains)
    }

    private static func identityTokens(in value: String) -> [String] {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }
}
