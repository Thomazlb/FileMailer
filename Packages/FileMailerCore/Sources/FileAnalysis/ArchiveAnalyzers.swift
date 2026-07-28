import FileMailerDomain
import Foundation
import ZIPFoundation

public struct ArchiveInspection: Sendable, Equatable {
    public let entryNames: [String]
    public let totalUncompressedSize: UInt64
    public let isSuspicious: Bool

    public init(entryNames: [String], totalUncompressedSize: UInt64, isSuspicious: Bool) {
        self.entryNames = entryNames
        self.totalUncompressedSize = totalUncompressedSize
        self.isSuspicious = isSuspicious
    }
}

public struct ArchiveSecurityInspector: Sendable {
    public init() {}

    public func inspect(url: URL, maximumEntries: Int = 500) throws -> ArchiveInspection {
        let archive = try Archive(url: url, accessMode: .read)
        var names: [String] = []
        var total: UInt64 = 0
        var suspicious = false
        for entry in archive {
            guard names.count < maximumEntries else {
                suspicious = true
                break
            }
            let path = entry.path
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            if path.hasPrefix("/") || components.contains("..") || entry.type == .symlink {
                suspicious = true
            }
            let (nextTotal, overflow) = total.addingReportingOverflow(entry.uncompressedSize)
            total = overflow ? .max : nextTotal
            if entry.uncompressedSize > 200 * 1_024 * 1_024 {
                suspicious = true
            }
            if entry.compressedSize > 0,
               entry.uncompressedSize / entry.compressedSize > 100 {
                suspicious = true
            }
            names.append(path)
        }
        if total > 500 * 1_024 * 1_024 { suspicious = true }
        return ArchiveInspection(
            entryNames: names,
            totalUncompressedSize: total,
            isSuspicious: suspicious
        )
    }
}

struct ArchiveManifestAnalyzer: Sendable {
    func analyze(url: URL, base: Metadata, policy: AnalysisPolicy) -> AttachmentAnalysis {
        do {
            let inspection = try ArchiveSecurityInspector().inspect(
                url: url,
                maximumEntries: policy.maximumArchiveEntries
            )
            let sample = inspection.entryNames.prefix(20).joined(separator: ", ")
            return AttachmentAnalysis(
                displayName: base.name,
                contentType: base.contentType,
                size: base.size,
                creationDate: base.creationDate,
                modificationDate: base.modificationDate,
                extractedText: nil,
                deterministicSummary: "Archive, \(inspection.entryNames.count) entrées. \(sample)",
                warnings: inspection.isSuspicious ? [.suspiciousArchive] : []
            )
        } catch {
            return AttachmentAnalysis(
                displayName: base.name,
                contentType: base.contentType,
                size: base.size,
                deterministicSummary: "Archive illisible.",
                warnings: [.inaccessible]
            )
        }
    }
}

struct OfficeOpenXMLAnalyzer: Sendable {
    func analyze(
        url: URL,
        base: Metadata,
        policy: AnalysisPolicy,
        remainingTextBytes: Int
    ) -> AttachmentAnalysis {
        do {
            let inspection = try ArchiveSecurityInspector().inspect(
                url: url,
                maximumEntries: policy.maximumArchiveEntries
            )
            guard !inspection.isSuspicious else {
                return suspicious(base)
            }
            let archive = try Archive(url: url, accessMode: .read)
            let extensionName = url.pathExtension.lowercased()
            let accepted: (String) -> Bool = { path in
                switch extensionName {
                case "docx":
                    path == "word/document.xml"
                        || path.hasPrefix("word/header")
                        || path.hasPrefix("word/footer")
                case "xlsx":
                    path == "xl/sharedStrings.xml"
                        || path == "xl/workbook.xml"
                        || path.hasPrefix("xl/worksheets/sheet")
                case "pptx":
                    path.hasPrefix("ppt/slides/slide")
                        || path.hasPrefix("ppt/notesSlides/notesSlide")
                default:
                    false
                }
            }
            var combined = Data()
            for entry in archive where accepted(entry.path) {
                guard combined.count < min(remainingTextBytes, 1_048_576),
                      entry.uncompressedSize <= 2 * 1_024 * 1_024
                else {
                    break
                }
                _ = try archive.extract(entry) { data in
                    let remaining = min(remainingTextBytes, 1_048_576) - combined.count
                    if remaining > 0 { combined.append(data.prefix(remaining)) }
                }
            }
            let xml = String(decoding: combined, as: UTF8.self)
            let text = XMLTextExtractor.extract(xml)
            return AttachmentAnalysis(
                displayName: base.name,
                contentType: base.contentType,
                size: base.size,
                creationDate: base.creationDate,
                modificationDate: base.modificationDate,
                extractedText: text,
                deterministicSummary: "\(extensionName.uppercased()) analysé sans exécuter Office, \(inspection.entryNames.count) entrées.",
                warnings: combined.count >= remainingTextBytes ? [.truncated] : [],
                includedInModel: !text.isEmpty
            )
        } catch {
            return AttachmentAnalysis(
                displayName: base.name,
                contentType: base.contentType,
                size: base.size,
                deterministicSummary: "Document Office Open XML illisible.",
                warnings: [.inaccessible]
            )
        }
    }

    private func suspicious(_ base: Metadata) -> AttachmentAnalysis {
        AttachmentAnalysis(
            displayName: base.name,
            contentType: base.contentType,
            size: base.size,
            deterministicSummary: "Document Office présentant une structure ZIP suspecte.",
            warnings: [.suspiciousArchive]
        )
    }
}

enum XMLTextExtractor {
    static func extract(_ input: String) -> String {
        input
            .replacingOccurrences(
                of: "<[^>]+>",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(
                of: "[\\t ]+",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\n{3,}",
                with: "\n\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
