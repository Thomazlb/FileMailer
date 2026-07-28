import FileMailerDomain
import Foundation

public struct DeterministicDraftGenerator: EmailDraftGenerating {
    public init() {}

    public func streamDraft(
        request: DraftGenerationRequest
    ) -> AsyncThrowingStream<GeneratedDraftSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let draft = generate(request)
            continuation.yield(draft)
            continuation.finish()
        }
    }

    public func generate(_ request: DraftGenerationRequest) -> GeneratedDraftSnapshot {
        let names = request.analyses.map(\.displayName)
        let french = request.language != .english
        let recipient = request.recipientName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let salutation: String
        if french {
            salutation = recipient.map { "Bonjour \($0)," } ?? "Bonjour,"
        } else {
            salutation = recipient.map { "Hello \($0)," } ?? "Hello,"
        }

        let subject: String
        let message: String
        let isOwnDocument = DraftIdentityResolver.documentsBelongToSender(request)
        let isResume = DraftIdentityResolver.isResume(request)
        if isOwnDocument && isResume {
            if french {
                subject = request.tone == .professional
                    ? "Transmission de mon CV"
                    : "Mon CV en pièce jointe"
                message = professionalized(
                    "Je me permets de vous transmettre mon CV en pièce jointe.",
                    request: request,
                    french: true
                )
            } else {
                subject = "My résumé"
                message = professionalized(
                    "Please find my résumé attached.",
                    request: request,
                    french: false
                )
            }
        } else if isResume {
            if french {
                subject = "Transmission du CV joint"
                message = professionalized(
                    "Je me permets de vous transmettre le CV en pièce jointe.",
                    request: request,
                    french: true
                )
            } else {
                subject = "Attached résumé"
                message = professionalized(
                    "Please find the résumé attached.",
                    request: request,
                    french: false
                )
            }
        } else if names.count == 1, let name = names.first {
            let nature = attachmentNature(request.analyses[0], french: french)
            if french {
                subject = "Transmission \(attachmentSubjectNature(request.analyses[0])) « \(name) »"
                message = professionalized(
                    "Je me permets de vous transmettre \(nature) « \(name) » en pièce jointe.",
                    request: request,
                    french: true
                )
            } else {
                subject = "Sending “\(name)”"
                message = professionalized(
                    "Please find \(nature) “\(name)” attached.",
                    request: request,
                    french: false
                )
            }
        } else if names.isEmpty {
            subject = french ? "Nouveau message" : "New message"
            message = french ? "Je vous écris au sujet de notre échange." : "I am writing regarding our conversation."
        } else {
            subject = french ? "Envoi des documents sélectionnés" : "Sending the selected documents"
            let list = names.map { "- \($0)" }.joined(separator: "\n")
            message = professionalized(
                french
                    ? "Je me permets de vous transmettre les documents suivants en pièces jointes :\n\(list)"
                    : "Please find the following documents attached:\n\(list)",
                request: request,
                french: french
            )
        }

        let closing = french ? "Bien cordialement," : "Kind regards,"
        let savedSignature = request.signature?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let senderName = request.senderName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = savedSignature?.isEmpty == false ? savedSignature : senderName
        let body = [salutation, "", message, "", closing, signature]
            .compactMap { $0 }
            .joined(separator: "\n")
        return GeneratedDraftSnapshot(
            subject: String(subject.prefix(120)),
            body: body,
            isFinal: true
        )
    }

    private func professionalized(
        _ message: String,
        request: DraftGenerationRequest,
        french: Bool
    ) -> String {
        guard request.tone == .professional else { return message }
        let availability = french
            ? "Je reste à votre disposition pour toute information complémentaire."
            : "Please let me know if you need any further information."
        return "\(message)\n\n\(availability)"
    }

    private func attachmentNature(
        _ analysis: AttachmentAnalysis,
        french: Bool
    ) -> String {
        let summary = analysis.deterministicSummary.lowercased()
        let type = analysis.contentType.lowercased()
        let name = analysis.displayName.lowercased()
        if summary.contains("dossier") {
            return french ? "le dossier" : "the folder"
        }
        if type.contains("zip") || type.contains("archive") {
            return french ? "l’archive" : "the archive"
        }
        if name.hasSuffix(".ppt") || name.hasSuffix(".pptx") {
            return french ? "la présentation" : "the presentation"
        }
        if name.hasSuffix(".xls") || name.hasSuffix(".xlsx") || name.hasSuffix(".csv") {
            return french ? "le tableau" : "the spreadsheet"
        }
        if type.hasPrefix("image/") {
            return french ? "l’image" : "the image"
        }
        if type == "application/pdf" {
            return french ? "le document PDF" : "the PDF document"
        }
        if name.hasSuffix(".doc") || name.hasSuffix(".docx") {
            return french ? "le document Word" : "the Word document"
        }
        if type.hasPrefix("text/") {
            return french ? "le document texte" : "the text document"
        }
        return french ? "le fichier" : "the file"
    }

    private func attachmentSubjectNature(_ analysis: AttachmentAnalysis) -> String {
        let summary = analysis.deterministicSummary.lowercased()
        let type = analysis.contentType.lowercased()
        let name = analysis.displayName.lowercased()
        if summary.contains("dossier") {
            return "du dossier"
        }
        if type.contains("zip") || type.contains("archive") {
            return "de l’archive"
        }
        if name.hasSuffix(".ppt") || name.hasSuffix(".pptx") {
            return "de la présentation"
        }
        if name.hasSuffix(".xls") || name.hasSuffix(".xlsx") || name.hasSuffix(".csv") {
            return "du tableau"
        }
        if type.hasPrefix("image/") {
            return "de l’image"
        }
        if type == "application/pdf" {
            return "du document PDF"
        }
        if name.hasSuffix(".doc") || name.hasSuffix(".docx") {
            return "du document Word"
        }
        if type.hasPrefix("text/") {
            return "du document texte"
        }
        return "du fichier"
    }
}
