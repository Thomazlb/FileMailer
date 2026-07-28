import FileMailerDomain
import Foundation
import SwiftData

@Model
public final class StoredGmailAccountMetadata {
    @Attribute(.unique) public var subject: String
    public var email: String
    public var displayName: String?
    public var isDefault: Bool
    public var lastUsedAt: Date?
    public var grantedScopes: [String]
    public var authStatusRaw: String
    public var signature: String?
    public var sortOrder: Int

    public init(_ account: GmailAccountSummary, sortOrder: Int = 0) {
        subject = account.id.rawValue
        email = account.email
        displayName = account.displayName
        isDefault = account.isDefault
        lastUsedAt = account.lastUsedAt
        grantedScopes = account.grantedScopes.sorted()
        authStatusRaw = account.authStatus.rawValue
        signature = account.signature
        self.sortOrder = sortOrder
    }

    public var domainValue: GmailAccountSummary {
        GmailAccountSummary(
            id: GmailAccountID(rawValue: subject),
            email: email,
            displayName: displayName,
            isDefault: isDefault,
            lastUsedAt: lastUsedAt,
            grantedScopes: Set(grantedScopes),
            authStatus: AuthStatus(rawValue: authStatusRaw) ?? .unavailable,
            signature: signature
        )
    }
}

@Model
public final class StoredRecipient {
    @Attribute(.unique) public var uuid: UUID
    public var displayName: String
    public var email: String
    public var normalizedEmail: String
    public var isPinned: Bool
    public var pinOrder: Int?
    public var isEnabled: Bool
    public var preferredSenderSubject: String?
    public var preferredToneRaw: String?
    public var customInstruction: String?
    public var localSendCount: Int
    public var sentLast30Days: Int
    public var sentLast180Days: Int
    public var lastSentAt: Date?

    public init(_ recipient: RecipientProfile) {
        uuid = recipient.id.rawValue
        displayName = recipient.displayName
        email = recipient.email
        normalizedEmail = recipient.normalizedEmail
        isPinned = recipient.isPinned
        pinOrder = recipient.pinOrder
        isEnabled = recipient.isEnabled
        preferredSenderSubject = recipient.preferredSenderID?.rawValue
        preferredToneRaw = recipient.preferredTone?.rawValue
        customInstruction = recipient.customInstruction
        localSendCount = recipient.localSendCount
        sentLast30Days = recipient.sentLast30Days
        sentLast180Days = recipient.sentLast180Days
        lastSentAt = recipient.lastSentAt
    }

    public func update(from recipient: RecipientProfile) {
        displayName = recipient.displayName
        email = recipient.email
        normalizedEmail = recipient.normalizedEmail
        isPinned = recipient.isPinned
        pinOrder = recipient.pinOrder
        isEnabled = recipient.isEnabled
        preferredSenderSubject = recipient.preferredSenderID?.rawValue
        preferredToneRaw = recipient.preferredTone?.rawValue
        customInstruction = recipient.customInstruction
        localSendCount = recipient.localSendCount
        sentLast30Days = recipient.sentLast30Days
        sentLast180Days = recipient.sentLast180Days
        lastSentAt = recipient.lastSentAt
    }

    public var domainValue: RecipientProfile {
        RecipientProfile(
            id: RecipientID(rawValue: uuid),
            displayName: displayName,
            email: email,
            normalizedEmail: normalizedEmail,
            isPinned: isPinned,
            pinOrder: pinOrder,
            isEnabled: isEnabled,
            preferredSenderID: preferredSenderSubject.map(GmailAccountID.init(rawValue:)),
            preferredTone: preferredToneRaw.flatMap(DraftTone.init(rawValue:)),
            customInstruction: customInstruction,
            localSendCount: localSendCount,
            sentLast30Days: sentLast30Days,
            sentLast180Days: sentLast180Days,
            lastSentAt: lastSentAt
        )
    }
}

@Model
public final class StoredSendEvent {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var accountSubject: String
    public var normalizedRecipient: String
    public var attachmentCount: Int
    public var totalSize: Int64
    public var contentCategories: [String]
    public var succeeded: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        accountID: GmailAccountID,
        normalizedRecipient: String,
        attachmentCount: Int,
        totalSize: Int64,
        contentCategories: [String],
        succeeded: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        accountSubject = accountID.rawValue
        self.normalizedRecipient = normalizedRecipient
        self.attachmentCount = attachmentCount
        self.totalSize = totalSize
        self.contentCategories = contentCategories
        self.succeeded = succeeded
    }
}

@Model
public final class StoredAppSettings {
    @Attribute(.unique) public var key: String
    public var visibleRecipientCount: Int
    public var autosaveDrafts: Bool
    public var launchAtLogin: Bool
    public var preferredLanguageRaw: String
    public var allowEnterprise50MB: Bool
    public var privateCloudComputeEnabled: Bool
    public var gmailHistoryImportEnabled: Bool

    public init(
        visibleRecipientCount: Int = 5,
        autosaveDrafts: Bool = false,
        launchAtLogin: Bool = false,
        preferredLanguage: DraftLanguage = .automatic
    ) {
        key = "settings"
        self.visibleRecipientCount = min(max(visibleRecipientCount, 1), 10)
        self.autosaveDrafts = autosaveDrafts
        self.launchAtLogin = launchAtLogin
        preferredLanguageRaw = preferredLanguage.rawValue
        allowEnterprise50MB = false
        privateCloudComputeEnabled = false
        gmailHistoryImportEnabled = false
    }
}

@Model
public final class StoredPendingDraft {
    @Attribute(.unique) public var id: UUID
    public var senderSubject: String?
    public var toAddresses: [String]
    public var ccAddresses: [String]
    public var bccAddresses: [String]
    public var subject: String
    public var body: String
    public var attachmentBookmarks: [Data]
    public var updatedAt: Date

    public init(
        id: UUID,
        senderSubject: String?,
        toAddresses: [String],
        ccAddresses: [String],
        bccAddresses: [String],
        subject: String,
        body: String,
        attachmentBookmarks: [Data],
        updatedAt: Date
    ) {
        self.id = id
        self.senderSubject = senderSubject
        self.toAddresses = toAddresses
        self.ccAddresses = ccAddresses
        self.bccAddresses = bccAddresses
        self.subject = subject
        self.body = body
        self.attachmentBookmarks = attachmentBookmarks
        self.updatedAt = updatedAt
    }
}

public enum FileMailerSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [
            StoredGmailAccountMetadata.self,
            StoredRecipient.self,
            StoredSendEvent.self,
            StoredAppSettings.self,
            StoredPendingDraft.self
        ]
    }
}

public enum FileMailerMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [FileMailerSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
