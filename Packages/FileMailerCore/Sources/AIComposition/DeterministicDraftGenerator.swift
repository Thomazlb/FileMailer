import FileMailerDomain
import Foundation

public struct DeterministicDraftGenerator: EmailDraftGenerating {
    public init() {}

    public func streamDraft(request: DraftGenerationRequest) -> AsyncThrowingStream<GeneratedDraftSnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(generate(request))
            continuation.finish()
        }
    }

    public func generate(_ request: DraftGenerationRequest) -> GeneratedDraftSnapshot {
        let localizer = FileMailerLocalization(languageIdentifier: DraftLanguageResolver.resolve(request))
        let recipient = request.recipientName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let salutation = recipient.flatMap { $0.isEmpty ? nil : $0 }
            .map { localizer.format("Bonjour %@,", $0) } ?? localizer.string("Bonjour,")
        let subject: String
        var message: String
        if DraftIdentityResolver.isResume(request) {
            let own = DraftIdentityResolver.documentsBelongToSender(request)
            subject = localizer.string(own ? "Transmission de mon CV" : "Transmission du CV joint")
            message = localizer.string(own
                ? "Je me permets de vous transmettre mon CV en pièce jointe."
                : "Je me permets de vous transmettre le CV en pièce jointe.")
        } else if request.analyses.count == 1, let analysis = request.analyses.first {
            subject = localizer.format("Envoi de « %@ »", analysis.displayName)
            message = localizer.format(attachmentMessage(analysis), analysis.displayName)
        } else if request.analyses.isEmpty {
            subject = localizer.string("Nouveau message")
            message = localizer.string("Je vous écris au sujet de notre échange.")
        } else {
            subject = localizer.string("Envoi des documents sélectionnés")
            message = localizer.string("Veuillez trouver les documents suivants en pièces jointes :")
                + "\n" + request.analyses.map { "- \($0.displayName)" }.joined(separator: "\n")
        }
        if request.tone == .professional {
            message += "\n\n" + localizer.string("Je reste à votre disposition pour toute information complémentaire.")
        }
        let savedSignature = request.signature?.trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = savedSignature?.isEmpty == false ? savedSignature
            : request.senderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = [salutation, "", message, "", localizer.string("Bien cordialement,"), signature]
            .compactMap { $0 }.joined(separator: "\n")
        return GeneratedDraftSnapshot(subject: String(subject.prefix(120)), body: body, isFinal: true)
    }

    private func attachmentMessage(_ analysis: AttachmentAnalysis) -> String {
        let type = analysis.contentType.lowercased()
        let name = analysis.displayName.lowercased()
        if type == "inode/directory" || analysis.deterministicSummary.hasPrefix("Dossier") {
            return "Je vous transmets le dossier « %@ » en pièce jointe."
        }
        if type.contains("zip") || type.contains("archive") {
            return "Je vous transmets l’archive « %@ » en pièce jointe."
        }
        if name.hasSuffix(".ppt") || name.hasSuffix(".pptx") {
            return "Je vous transmets la présentation « %@ » en pièce jointe."
        }
        if [".xls", ".xlsx", ".csv"].contains(where: name.hasSuffix) {
            return "Je vous transmets le tableau « %@ » en pièce jointe."
        }
        if type.hasPrefix("image/") { return "Je vous transmets l’image « %@ » en pièce jointe." }
        if type == "application/pdf" { return "Je vous transmets le document PDF « %@ » en pièce jointe." }
        if name.hasSuffix(".doc") || name.hasSuffix(".docx") {
            return "Je vous transmets le document Word « %@ » en pièce jointe."
        }
        if type.hasPrefix("text/") { return "Je vous transmets le document texte « %@ » en pièce jointe." }
        return "Je vous transmets le fichier « %@ » en pièce jointe."
    }
}
