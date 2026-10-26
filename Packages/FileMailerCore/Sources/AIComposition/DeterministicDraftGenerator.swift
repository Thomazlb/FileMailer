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
            .map { localizer.format("Hello %@,", $0) } ?? localizer.string("Hello,")
        let subject: String
        var message: String
        if DraftIdentityResolver.isResume(request) {
            let own = DraftIdentityResolver.documentsBelongToSender(request)
            subject = localizer.string(own ? "My résumé" : "Attached résumé")
            message = localizer.string(own
                ? "Please find my résumé attached."
                : "Please find the résumé attached.")
        } else if request.analyses.count == 1, let analysis = request.analyses.first {
            subject = localizer.format("Sending “%@”", analysis.displayName)
            message = localizer.format(attachmentMessage(analysis), analysis.displayName)
        } else if request.analyses.isEmpty {
            subject = localizer.string("New message")
            message = localizer.string("I am writing regarding our conversation.")
        } else {
            subject = localizer.string("Sending selected documents")
            message = localizer.string("Please find the following documents attached:")
                + "\n" + request.analyses.map { "- \($0.displayName)" }.joined(separator: "\n")
        }
        if request.tone == .professional {
            message += "\n\n" + localizer.string("Please let me know if you need any further information.")
        }
        let savedSignature = request.signature?.trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = savedSignature?.isEmpty == false ? savedSignature
            : request.senderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = [salutation, "", message, "", localizer.string("Kind regards,"), signature]
            .compactMap { $0 }.joined(separator: "\n")
        return GeneratedDraftSnapshot(subject: String(subject.prefix(120)), body: body, isFinal: true)
    }

    private func attachmentMessage(_ analysis: AttachmentAnalysis) -> String {
        let type = analysis.contentType.lowercased()
        let name = analysis.displayName.lowercased()
        if type == "inode/directory" || analysis.deterministicSummary.hasPrefix("Dossier") {
            return "Please find the folder “%@” attached."
        }
        if type.contains("zip") || type.contains("archive") {
            return "Please find the archive “%@” attached."
        }
        if name.hasSuffix(".ppt") || name.hasSuffix(".pptx") {
            return "Please find the presentation “%@” attached."
        }
        if [".xls", ".xlsx", ".csv"].contains(where: name.hasSuffix) {
            return "Please find the spreadsheet “%@” attached."
        }
        if type.hasPrefix("image/") { return "Please find the image “%@” attached." }
        if type == "application/pdf" { return "Please find the PDF document “%@” attached." }
        if name.hasSuffix(".doc") || name.hasSuffix(".docx") {
            return "Please find the Word document “%@” attached."
        }
        if type.hasPrefix("text/") { return "Please find the text document “%@” attached." }
        return "Please find the file “%@” attached."
    }
}
