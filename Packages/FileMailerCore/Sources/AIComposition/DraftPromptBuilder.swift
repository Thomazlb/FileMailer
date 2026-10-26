import FileMailerDomain
import Foundation

public struct DraftPromptBuilder: Sendable {
    public var maximumCharacters: Int

    public init(maximumCharacters: Int = 24_000) {
        self.maximumCharacters = maximumCharacters
    }

    public func build(_ request: DraftGenerationRequest) -> String {
        let languageIdentifier = DraftLanguageResolver.resolve(request)
        let language = Locale(identifier: "en").localizedString(forIdentifier: languageIdentifier)
            ?? languageIdentifier
        var sections = [
            "REQUIRED OUTPUT LANGUAGE: \(language) [\(languageIdentifier)]. Write the entire subject and body in this language, including the greeting and closing. The language of examples or files must never override it.",
            "TONE: \(request.tone.rawValue)",
            "RECIPIENT: \(clean(request.recipientName ?? "not specified"))",
            "SENDER: \(clean(request.senderName ?? "not specified"))"
        ]
        if DraftIdentityResolver.documentsBelongToSender(request) {
            sections.append(
                """
                DOCUMENT OWNERSHIP: CONFIRMED. The documents concern the sender personally.
                Write the subject and message from the sender's perspective, using first-person wording in the required output language. Never refer to the sender's own resume as if it belonged to a third person.
                """
            )
        } else {
            sections.append(
                """
                DOCUMENT OWNERSHIP: NOT ESTABLISHED. Do not claim the documents belong to the sender. If the content explicitly identifies their owner, distinguish that person from the sender.
                """
            )
        }
        if let purpose = request.userPurpose, !purpose.isEmpty {
            sections.append("USER PURPOSE: \(clean(purpose))")
        }
        if let instruction = request.customInstruction, !instruction.isEmpty {
            sections.append("USER PREFERENCE: \(clean(instruction))")
        }
        if DraftIdentityResolver.isResume(request) {
            let ownership = DraftIdentityResolver.documentsBelongToSender(request)
                ? "This is the sender's resume."
                : "This resume belongs to another person, or its owner is not established."
            sections.append(
                """
                DOCUMENT TYPE: RESUME. \(ownership)
                By default, do not summarize work experience, skills, education, projects or other resume details in the email.
                Politely introduce the attached resume. In a professional tone, offer to provide further information. Include resume details only when the USER PURPOSE explicitly requests them.
                """
            )
        }
        sections.append(
            """
            ATTACHMENT WORDING:
            Use the known document type rather than generic wording. Distinguish a resume, folder, archive, presentation, spreadsheet, image, text document and PDF.
            For one item, mention its type and, when natural, its name. For multiple items, refer to the attached documents or items without an unnecessary technical list.
            Do not explain or summarize detailed attachment content unless the USER PURPOSE requests it.
            """
        )
        sections.append("")
        sections.append("ATTACHMENTS:")
        for (index, analysis) in request.analyses.enumerated() {
            sections.append(
                "\(index + 1). Kind: \(attachmentNature(analysis)). Name: \(clean(analysis.displayName)). Type: \(clean(analysis.contentType)). Size: \(analysis.size) bytes. Analysis: \(clean(analysis.deterministicSummary))"
            )
        }
        sections.append("")
        sections.append("<UNTRUSTED_FILE_DATA>")
        let fixedLength = sections.joined(separator: "\n").count + 1_500
        var remaining = max(0, maximumCharacters - fixedLength)
        for analysis in request.analyses {
            guard remaining > 0, let text = analysis.extractedText, !text.isEmpty else { continue }
            let excerpt = String(clean(text).prefix(min(remaining, 4_000)))
            sections.append("[\(clean(analysis.displayName))]\n\(excerpt)")
            remaining -= excerpt.count
        }
        sections.append("</UNTRUSTED_FILE_DATA>")
        sections.append("")
        let structure = DraftIdentityResolver.isResume(request)
            ? """
              REQUIRED RESUME EMAIL STRUCTURE:
              1. A greeting on its own line.
              2. A blank line.
              3. One or two short, natural sentences introducing the resume without summarizing it.
              4. For a professional tone, a sentence offering to provide further information.
              5. A blank line.
              6. A closing on its own line.
              """
            : """
              REQUIRED STRUCTURE:
              1. A greeting on its own line.
              2. A blank line.
              3. Two to four short paragraphs separated by blank lines.
              4. A blank line.
              5. A closing on its own line.
              """
        sections.append(
            """
            Write a faithful plain-text draft. Do not add unsupported facts, recipients or claims that the email was sent.
            \(structure)
            Do not write the signature: the application appends it automatically.
            """
        )
        return String(sections.joined(separator: "\n").prefix(maximumCharacters))
    }

    private func attachmentNature(_ analysis: AttachmentAnalysis) -> String {
        let type = analysis.contentType.lowercased()
        let name = analysis.displayName.lowercased()
        if type == "inode/directory" { return "folder" }
        if type.contains("zip") || type.contains("archive") { return "archive" }
        if name.hasSuffix(".ppt") || name.hasSuffix(".pptx") { return "presentation" }
        if name.hasSuffix(".xls") || name.hasSuffix(".xlsx") || name.hasSuffix(".csv") {
            return "spreadsheet"
        }
        if type.hasPrefix("image/") { return "image" }
        if DraftIdentityResolver.isResumeAnalysis(analysis) { return "resume" }
        if type == "application/pdf" { return "PDF document" }
        if name.hasSuffix(".doc") || name.hasSuffix(".docx") { return "Word document" }
        if type.hasPrefix("text/") { return "text document" }
        return "file"
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
