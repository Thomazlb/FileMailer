import Foundation

public enum AnalysisWarning: String, Codable, Sendable, Hashable {
    case inaccessible
    case encrypted
    case truncated
    case suspiciousArchive
    case sensitiveFile
    case symlinkOutsideRoot
    case unsupported
}

public struct AttachmentAnalysis: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var displayName: String
    public var contentType: String
    public var size: Int64
    public var creationDate: Date?
    public var modificationDate: Date?
    public var pageCount: Int?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var extractedText: String?
    public var deterministicSummary: String
    public var warnings: Set<AnalysisWarning>
    public var includedInModel: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        contentType: String,
        size: Int64,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        pageCount: Int? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        extractedText: String? = nil,
        deterministicSummary: String,
        warnings: Set<AnalysisWarning> = [],
        includedInModel: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.contentType = contentType
        self.size = size
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pageCount = pageCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.extractedText = extractedText
        self.deterministicSummary = deterministicSummary
        self.warnings = warnings
        self.includedInModel = includedInModel
    }
}

public struct AnalysisPolicy: Codable, Sendable {
    public var maximumPaths: Int
    public var maximumBytesPerTextFile: Int
    public var maximumExtractedTextBytes: Int
    public var maximumPDFPages: Int
    public var maximumOCRPages: Int
    public var maximumArchiveEntries: Int
    public var maximumFolderEntries: Int
    public var maximumFolderDepth: Int

    public init(
        maximumPaths: Int = 50,
        maximumBytesPerTextFile: Int = 256 * 1024,
        maximumExtractedTextBytes: Int = 1_048_576,
        maximumPDFPages: Int = 30,
        maximumOCRPages: Int = 10,
        maximumArchiveEntries: Int = 500,
        maximumFolderEntries: Int = 200,
        maximumFolderDepth: Int = 4
    ) {
        self.maximumPaths = maximumPaths
        self.maximumBytesPerTextFile = maximumBytesPerTextFile
        self.maximumExtractedTextBytes = maximumExtractedTextBytes
        self.maximumPDFPages = maximumPDFPages
        self.maximumOCRPages = maximumOCRPages
        self.maximumArchiveEntries = maximumArchiveEntries
        self.maximumFolderEntries = maximumFolderEntries
        self.maximumFolderDepth = maximumFolderDepth
    }
}

public struct DraftGenerationRequest: Sendable {
    public var language: DraftLanguage
    public var tone: DraftTone
    public var recipientName: String?
    public var senderName: String?
    public var userPurpose: String?
    public var customInstruction: String?
    public var analyses: [AttachmentAnalysis]
    public var signature: String?

    public init(
        language: DraftLanguage,
        tone: DraftTone,
        recipientName: String? = nil,
        senderName: String? = nil,
        userPurpose: String? = nil,
        customInstruction: String? = nil,
        analyses: [AttachmentAnalysis],
        signature: String? = nil
    ) {
        self.language = language
        self.tone = tone
        self.recipientName = recipientName
        self.senderName = senderName
        self.userPurpose = userPurpose
        self.customInstruction = customInstruction
        self.analyses = analyses
        self.signature = signature
    }
}

public struct GeneratedDraftSnapshot: Sendable, Equatable {
    public var subject: String
    public var body: String
    public var isFinal: Bool

    public init(subject: String, body: String, isFinal: Bool) {
        self.subject = subject
        self.body = body
        self.isFinal = isFinal
    }
}
