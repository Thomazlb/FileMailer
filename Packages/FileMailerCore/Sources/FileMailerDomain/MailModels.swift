import Foundation

public enum EmailAddressError: Error, LocalizedError, Equatable, Sendable {
    case empty
    case invalid
    case headerInjection
    case tooLong

    public var errorDescription: String? {
        switch self {
        case .empty: "L’adresse e-mail est vide."
        case .invalid: "L’adresse e-mail n’est pas valide."
        case .headerInjection: "L’adresse contient un caractère interdit."
        case .tooLong: "L’adresse e-mail est trop longue."
        }
    }
}

public struct EmailAddress: Hashable, Codable, Sendable, Identifiable {
    public let address: String
    public var displayName: String?
    public var id: String { normalized }
    public var normalized: String { Self.normalized(address) }

    public init(_ input: String, displayName: String? = nil) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw EmailAddressError.empty }
        guard value.utf8.count <= 254 else { throw EmailAddressError.tooLong }
        guard !value.unicodeScalars.contains(where: {
            $0.value == 0 || $0.value == 10 || $0.value == 13
        }) else {
            throw EmailAddressError.headerInjection
        }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[0].utf8.count <= 64,
              !parts[1].isEmpty,
              parts[1].contains("."),
              !parts[1].hasPrefix("."),
              !parts[1].hasSuffix("."),
              !parts[1].contains(".."),
              !parts[0].contains(" "),
              !parts[1].contains(" ")
        else {
            throw EmailAddressError.invalid
        }
        self.address = value.precomposedStringWithCanonicalMapping
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalized(_ input: String) -> String {
        let value = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard let separator = value.lastIndex(of: "@") else {
            return value.lowercased()
        }
        let local = value[..<separator].lowercased()
        let domain = value[value.index(after: separator)...].lowercased()
        return "\(local)@\(domain)"
    }

    public var headerValue: String {
        guard let displayName, !displayName.isEmpty else { return address }
        let safe = displayName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        return "\"\(safe)\" <\(address)>"
    }
}

public struct ComposeAttachment: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var url: URL
    public var displayName: String
    public var contentType: String
    public var size: Int64
    public var modificationDate: Date?
    public var isTemporary: Bool
    public var warning: String?
    public var deliveryMode: AttachmentDeliveryMode
    public var driveAccessExpiry: DriveAccessExpiry
    public var customDriveAccessExpiry: Date?
    public var driveCleanupAction: DriveCleanupAction
    public var driveFile: DriveFileReference?

    public init(
        id: UUID = UUID(),
        url: URL,
        displayName: String? = nil,
        contentType: String = "application/octet-stream",
        size: Int64 = 0,
        modificationDate: Date? = nil,
        isTemporary: Bool = false,
        warning: String? = nil,
        deliveryMode: AttachmentDeliveryMode = .attachment,
        driveAccessExpiry: DriveAccessExpiry = .never,
        customDriveAccessExpiry: Date? = nil,
        driveCleanupAction: DriveCleanupAction = .keep,
        driveFile: DriveFileReference? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.contentType = contentType
        self.size = size
        self.modificationDate = modificationDate
        self.isTemporary = isTemporary
        self.warning = warning
        self.deliveryMode = deliveryMode
        self.driveAccessExpiry = driveAccessExpiry
        self.customDriveAccessExpiry = customDriveAccessExpiry
        self.driveCleanupAction = driveCleanupAction
        self.driveFile = driveFile
    }

    public var usesGoogleDrive: Bool {
        deliveryMode == .googleDrive
    }

    public func resolvedDriveAccessExpiry(from date: Date = Date()) -> Date? {
        driveAccessExpiry.resolvedDate(
            customDate: customDriveAccessExpiry,
            referenceDate: date
        )
    }
}

public enum AttachmentDeliveryMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case attachment
    case googleDrive

    public var id: String { rawValue }
}

public enum DriveAccessExpiry: String, Codable, Sendable, CaseIterable, Identifiable {
    case never
    case oneDay
    case sevenDays
    case thirtyDays
    case ninetyDays
    case custom

    public var id: String { rawValue }

    public func resolvedDate(customDate: Date?, referenceDate: Date) -> Date? {
        let calendar = Calendar.current
        return switch self {
        case .never:
            nil
        case .oneDay:
            calendar.date(byAdding: .day, value: 1, to: referenceDate)
        case .sevenDays:
            calendar.date(byAdding: .day, value: 7, to: referenceDate)
        case .thirtyDays:
            calendar.date(byAdding: .day, value: 30, to: referenceDate)
        case .ninetyDays:
            calendar.date(byAdding: .day, value: 90, to: referenceDate)
        case .custom:
            customDate
        }
    }
}

public enum DriveCleanupAction: String, Codable, Sendable, CaseIterable, Identifiable {
    case keep
    case trash
    case delete

    public var id: String { rawValue }
}

public struct DriveFileReference: Codable, Sendable, Hashable {
    public let id: String
    public let webViewURL: URL
    public let accountID: GmailAccountID
    public let uploadedAt: Date

    public init(
        id: String,
        webViewURL: URL,
        accountID: GmailAccountID,
        uploadedAt: Date = Date()
    ) {
        self.id = id
        self.webViewURL = webViewURL
        self.accountID = accountID
        self.uploadedAt = uploadedAt
    }
}

public enum AttachmentDeliveryPolicy {
    // Gmail encodes attachments for MIME transport. Keeping the direct threshold below
    // Gmail's published limit prevents otherwise valid files from becoming oversized.
    public static let directAttachmentLimit: Int64 = 18 * 1_024 * 1_024

    // Gmail rejects executable, installer, disk-image, and archive payloads. Those
    // messages can appear to send successfully before Gmail returns a delivery
    // failure, so route them through Drive before the message is constructed.
    private static let linkOnlyExtensions: Set<String> = [
        "7z", "app", "bat", "bin", "bz2", "cmd", "com", "command", "dmg", "dll",
        "dylib", "exe", "gz", "img", "ipa", "iso", "jar", "jse", "js", "kext",
        "mpkg", "msi", "msix", "pkg", "pif", "ps1", "psm1", "rar", "scr", "sh",
        "so", "tar", "vbe", "vbs", "wsh", "wsf", "xip", "xz", "zip"
    ]

    private static let linkOnlyMIMETypes = [
        "diskimage", "x-apple-installer", "x-dosexec", "x-msdownload", "x-sh"
    ]

    public static func requiresLinkDelivery(for attachment: ComposeAttachment) -> Bool {
        let fileExtension = attachment.url.pathExtension.lowercased()
        let mimeType = attachment.contentType.lowercased()
        return linkOnlyExtensions.contains(fileExtension)
            || linkOnlyMIMETypes.contains { mimeType.contains($0) }
    }

    public static func usesGoogleDriveByDefault(for attachment: ComposeAttachment) -> Bool {
        attachment.size > directAttachmentLimit || requiresLinkDelivery(for: attachment)
    }
}

public enum DraftGenerationState: String, Codable, Sendable {
    case manual
    case analyzing
    case generating
    case generated
    case suggestionAvailable
    case unavailable
    case failed
}

public enum DraftLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case automatic
    case french
    case english

    public var id: String { rawValue }
}

public struct ComposeDraft: Identifiable, Codable, Sendable {
    public let id: UUID
    public var senderID: GmailAccountID?
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var bcc: [EmailAddress]
    public var subject: String
    public var body: String
    public var attachments: [ComposeAttachment]
    public var generationState: DraftGenerationState
    public var userRevision: UInt64

    public init(
        id: UUID = UUID(),
        senderID: GmailAccountID? = nil,
        to: [EmailAddress] = [],
        cc: [EmailAddress] = [],
        bcc: [EmailAddress] = [],
        subject: String = "",
        body: String = "",
        attachments: [ComposeAttachment] = [],
        generationState: DraftGenerationState = .manual,
        userRevision: UInt64 = 0
    ) {
        self.id = id
        self.senderID = senderID
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.attachments = attachments
        self.generationState = generationState
        self.userRevision = userRevision
    }

    public func outboundSnapshot(from sender: EmailAddress) throws -> OutboundMessage {
        guard !to.isEmpty, to.count + cc.count + bcc.count <= 50 else {
            throw OutboundMessageError.invalidRecipients
        }
        guard !subject.contains("\r"), !subject.contains("\n") else {
            throw OutboundMessageError.headerInjection
        }
        return OutboundMessage(
            id: UUID(),
            sender: sender,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            body: body,
            attachments: attachments,
            capturedRevision: userRevision
        )
    }
}

public enum OutboundMessageError: Error, LocalizedError, Equatable, Sendable {
    case invalidRecipients
    case headerInjection
    case emptySubjectAndBody
    case attachmentChanged(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRecipients: "Ajoutez au moins un destinataire valide."
        case .headerInjection: "Un en-tête contient un caractère interdit."
        case .emptySubjectAndBody: "L’objet et le message sont vides."
        case let .attachmentChanged(name): "La pièce jointe « \(name) » a changé."
        }
    }
}

public struct OutboundMessage: Identifiable, Sendable {
    public let id: UUID
    public let sender: EmailAddress
    public let to: [EmailAddress]
    public let cc: [EmailAddress]
    public let bcc: [EmailAddress]
    public let subject: String
    public let body: String
    public let attachments: [ComposeAttachment]
    public let capturedRevision: UInt64

    public init(
        id: UUID,
        sender: EmailAddress,
        to: [EmailAddress],
        cc: [EmailAddress],
        bcc: [EmailAddress],
        subject: String,
        body: String,
        attachments: [ComposeAttachment],
        capturedRevision: UInt64
    ) {
        self.id = id
        self.sender = sender
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.attachments = attachments
        self.capturedRevision = capturedRevision
    }
}
