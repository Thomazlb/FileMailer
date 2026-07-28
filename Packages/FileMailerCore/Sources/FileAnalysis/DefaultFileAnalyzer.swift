import AppKit
import FileMailerDomain
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
@preconcurrency import Vision
import ZIPFoundation

public enum FileAnalysisError: Error, LocalizedError, Sendable {
    case tooManyPaths
    case archiveInvalid
    case archiveSuspicious
    case folderTooLarge
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .tooManyPaths: "Trop de fichiers ont été sélectionnés."
        case .archiveInvalid: "L’archive ne peut pas être lue."
        case .archiveSuspicious: "L’archive présente un risque de sécurité."
        case .folderTooLarge: "Le dossier dépasse les limites d’analyse."
        case .cancelled: "L’analyse a été annulée."
        }
    }
}

public actor DefaultFileAnalyzer: FileAnalyzing {
    public init() {}

    public func analyze(
        urls: [URL],
        policy: AnalysisPolicy
    ) async throws -> [AttachmentAnalysis] {
        guard urls.count <= policy.maximumPaths else { throw FileAnalysisError.tooManyPaths }
        var remainingTextBytes = policy.maximumExtractedTextBytes
        var results: [AttachmentAnalysis] = []
        for url in urls {
            try Task.checkCancellation()
            let analysis = await analyzeOne(
                url,
                policy: policy,
                remainingTextBytes: remainingTextBytes
            )
            if let text = analysis.extractedText {
                remainingTextBytes = max(0, remainingTextBytes - text.utf8.count)
            }
            results.append(analysis)
        }
        return results
    }

    private func analyzeOne(
        _ url: URL,
        policy: AnalysisPolicy,
        remainingTextBytes: Int
    ) async -> AttachmentAnalysis {
        let keys: Set<URLResourceKey> = [
            .nameKey, .fileSizeKey, .contentTypeKey, .creationDateKey,
            .contentModificationDateKey, .isDirectoryKey, .isPackageKey,
            .isSymbolicLinkKey, .isReadableKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return inaccessible(url)
        }
        let name = values.name ?? url.lastPathComponent
        let type = values.contentType ?? UTType(filenameExtension: url.pathExtension)
        let contentType = type?.preferredMIMEType ?? "application/octet-stream"
        let size = Int64(values.fileSize ?? 0)
        let base = Metadata(
            name: name,
            contentType: contentType,
            size: size,
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate
        )
        guard values.isReadable != false else { return inaccessible(url, base: base) }

        if values.isDirectory == true {
            return FolderInspector().analyze(url: url, base: base, policy: policy)
        }
        if values.isSymbolicLink == true {
            return AttachmentAnalysis(
                displayName: name,
                contentType: contentType,
                size: size,
                creationDate: values.creationDate,
                modificationDate: values.contentModificationDate,
                deterministicSummary: "Lien symbolique, non suivi automatiquement.",
                warnings: [.symlinkOutsideRoot]
            )
        }
        if type?.conforms(to: .pdf) == true {
            return await PDFFileAnalyzer().analyze(
                url: url,
                base: base,
                policy: policy,
                remainingTextBytes: remainingTextBytes
            )
        }
        if type?.conforms(to: .image) == true {
            return await ImageFileAnalyzer().analyze(
                url: url,
                base: base,
                remainingTextBytes: remainingTextBytes
            )
        }
        let extensionName = url.pathExtension.lowercased()
        if ["docx", "xlsx", "pptx"].contains(extensionName) {
            return OfficeOpenXMLAnalyzer().analyze(
                url: url,
                base: base,
                policy: policy,
                remainingTextBytes: remainingTextBytes
            )
        }
        if type?.conforms(to: .archive) == true || extensionName == "zip" {
            return ArchiveManifestAnalyzer().analyze(url: url, base: base, policy: policy)
        }
        if isText(type: type, extensionName: extensionName) {
            return PlainTextAnalyzer().analyze(
                url: url,
                base: base,
                maximumBytes: min(policy.maximumBytesPerTextFile, remainingTextBytes)
            )
        }
        return AttachmentAnalysis(
            displayName: name,
            contentType: contentType,
            size: size,
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            deterministicSummary: "Fichier \(contentType), \(size) octets.",
            warnings: [.unsupported]
        )
    }

    private func isText(type: UTType?, extensionName: String) -> Bool {
        if type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true {
            return true
        }
        return [
            "txt", "md", "csv", "json", "xml", "yaml", "yml", "swift", "m", "mm",
            "h", "py", "js", "ts", "tsx", "jsx", "rs", "go", "java", "kt", "c", "cpp"
        ].contains(extensionName)
    }

    private func inaccessible(_ url: URL, base: Metadata? = nil) -> AttachmentAnalysis {
        AttachmentAnalysis(
            displayName: base?.name ?? url.lastPathComponent,
            contentType: base?.contentType ?? "application/octet-stream",
            size: base?.size ?? 0,
            creationDate: base?.creationDate,
            modificationDate: base?.modificationDate,
            deterministicSummary: "Fichier inaccessible. Sélectionnez-le à nouveau.",
            warnings: [.inaccessible]
        )
    }
}

struct Metadata: Sendable {
    let name: String
    let contentType: String
    let size: Int64
    let creationDate: Date?
    let modificationDate: Date?
}

struct PlainTextAnalyzer: Sendable {
    func analyze(url: URL, base: Metadata, maximumBytes: Int) -> AttachmentAnalysis {
        guard maximumBytes > 0,
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            return unavailable(base)
        }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: maximumBytes + 1)) ?? Data()
        let truncated = data.count > maximumBytes
        let bounded = data.prefix(maximumBytes)
        let text = decode(Data(bounded))
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return AttachmentAnalysis(
            displayName: base.name,
            contentType: base.contentType,
            size: base.size,
            creationDate: base.creationDate,
            modificationDate: base.modificationDate,
            extractedText: text,
            deterministicSummary: "Document texte, \(text.split(separator: "\n").count) lignes\(truncated ? ", extrait tronqué" : "").",
            warnings: truncated ? [.truncated] : [],
            includedInModel: !text.isEmpty
        )
    }

    private func decode(_ data: Data) -> String {
        if let value = String(data: data, encoding: .utf8) { return value }
        if let value = String(data: data, encoding: .utf16) { return value }
        if let value = String(data: data, encoding: .windowsCP1252) { return value }
        return String(decoding: data, as: UTF8.self)
    }

    private func unavailable(_ base: Metadata) -> AttachmentAnalysis {
        AttachmentAnalysis(
            displayName: base.name,
            contentType: base.contentType,
            size: base.size,
            creationDate: base.creationDate,
            modificationDate: base.modificationDate,
            deterministicSummary: "Document texte inaccessible.",
            warnings: [.inaccessible]
        )
    }
}

struct PDFFileAnalyzer: Sendable {
    func analyze(
        url: URL,
        base: Metadata,
        policy: AnalysisPolicy,
        remainingTextBytes: Int
    ) async -> AttachmentAnalysis {
        guard let document = PDFDocument(url: url) else {
            return AttachmentAnalysis(
                displayName: base.name,
                contentType: base.contentType,
                size: base.size,
                deterministicSummary: "PDF illisible.",
                warnings: [.inaccessible]
            )
        }
        if document.isEncrypted, document.isLocked {
            return AttachmentAnalysis(
                displayName: base.name,
                contentType: base.contentType,
                size: base.size,
                pageCount: document.pageCount,
                deterministicSummary: "PDF chiffré, \(document.pageCount) pages.",
                warnings: [.encrypted]
            )
        }
        let pageLimit = min(document.pageCount, policy.maximumPDFPages)
        var pageTexts: [String] = []
        var ocrPages = 0
        for index in 0..<pageLimit {
            if Task.isCancelled { break }
            guard let page = document.page(at: index) else { continue }
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty {
                pageTexts.append(text)
            } else if ocrPages < policy.maximumOCRPages,
                      let image = page.thumbnail(
                        of: NSSize(width: 1_600, height: 2_000),
                        for: .mediaBox
                      ).cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let recognized = try? await VisionTextRecognizer.recognize(image),
                      !recognized.isEmpty {
                pageTexts.append(recognized)
                ocrPages += 1
            }
        }
        let joined = String(
            pageTexts.joined(separator: "\n\n").prefix(max(0, remainingTextBytes))
        )
        var warnings = Set<AnalysisWarning>()
        if document.pageCount > pageLimit || joined.utf8.count >= remainingTextBytes {
            warnings.insert(.truncated)
        }
        return AttachmentAnalysis(
            displayName: base.name,
            contentType: base.contentType,
            size: base.size,
            creationDate: base.creationDate,
            modificationDate: base.modificationDate,
            pageCount: document.pageCount,
            extractedText: joined,
            deterministicSummary: "PDF, \(document.pageCount) pages, texte extrait de \(pageTexts.count) pages.",
            warnings: warnings,
            includedInModel: !joined.isEmpty
        )
    }
}

struct ImageFileAnalyzer: Sendable {
    func analyze(
        url: URL,
        base: Metadata,
        remainingTextBytes: Int
    ) async -> AttachmentAnalysis {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return AttachmentAnalysis(
                displayName: base.name,
                contentType: base.contentType,
                size: base.size,
                deterministicSummary: "Image illisible.",
                warnings: [.inaccessible]
            )
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        let recognized = (try? await VisionTextRecognizer.recognize(image)) ?? ""
        let text = String(recognized.prefix(max(0, remainingTextBytes)))
        return AttachmentAnalysis(
            displayName: base.name,
            contentType: base.contentType,
            size: base.size,
            creationDate: base.creationDate,
            modificationDate: base.modificationDate,
            pixelWidth: width,
            pixelHeight: height,
            extractedText: text.isEmpty ? nil : text,
            deterministicSummary: "Image \(width ?? 0) × \(height ?? 0) pixels\(text.isEmpty ? "" : ", texte OCR détecté").",
            includedInModel: !text.isEmpty
        )
    }
}

private final class VisionRecognitionContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func succeed(with text: String) {
        finish(.success(text))
    }

    func fail(with error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

enum VisionTextRecognizer {
    static func recognize(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let completion = VisionRecognitionContinuation(continuation)
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    completion.fail(with: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                completion.succeed(with: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                completion.fail(with: error)
            }
        }
    }
}
