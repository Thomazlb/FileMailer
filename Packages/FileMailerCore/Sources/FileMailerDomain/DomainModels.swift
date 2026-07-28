import Foundation

public struct GmailAccountID: Hashable, Codable, Sendable, Identifiable {
    public let rawValue: String
    public var id: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum AuthStatus: String, Codable, Sendable, CaseIterable {
    case connected
    case needsReauthentication
    case revoked
    case unavailable
}

public struct GmailAccountSummary: Identifiable, Codable, Sendable, Hashable {
    public let id: GmailAccountID
    public var email: String
    public var displayName: String?
    public var isDefault: Bool
    public var lastUsedAt: Date?
    public var grantedScopes: Set<String>
    public var authStatus: AuthStatus
    public var signature: String?

    public init(
        id: GmailAccountID,
        email: String,
        displayName: String? = nil,
        isDefault: Bool = false,
        lastUsedAt: Date? = nil,
        grantedScopes: Set<String> = [],
        authStatus: AuthStatus = .connected,
        signature: String? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.isDefault = isDefault
        self.lastUsedAt = lastUsedAt
        self.grantedScopes = grantedScopes
        self.authStatus = authStatus
        self.signature = signature
    }
}

public struct RecipientID: Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID
    public var id: UUID { rawValue }

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum DraftTone: String, Codable, Sendable, CaseIterable, Identifiable {
    case concise
    case professional
    case friendly
    case neutral

    public var id: String { rawValue }
}

public struct RecipientProfile: Identifiable, Codable, Sendable, Hashable {
    public let id: RecipientID
    public var displayName: String
    public var email: String
    public var normalizedEmail: String
    public var isPinned: Bool
    public var pinOrder: Int?
    public var isEnabled: Bool
    public var preferredSenderID: GmailAccountID?
    public var preferredTone: DraftTone?
    public var customInstruction: String?
    public var localSendCount: Int
    public var sentLast30Days: Int
    public var sentLast180Days: Int
    public var lastSentAt: Date?

    public init(
        id: RecipientID = RecipientID(),
        displayName: String,
        email: String,
        normalizedEmail: String? = nil,
        isPinned: Bool = false,
        pinOrder: Int? = nil,
        isEnabled: Bool = true,
        preferredSenderID: GmailAccountID? = nil,
        preferredTone: DraftTone? = nil,
        customInstruction: String? = nil,
        localSendCount: Int = 0,
        sentLast30Days: Int = 0,
        sentLast180Days: Int = 0,
        lastSentAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.normalizedEmail = normalizedEmail ?? EmailAddress.normalized(email)
        self.isPinned = isPinned
        self.pinOrder = pinOrder
        self.isEnabled = isEnabled
        self.preferredSenderID = preferredSenderID
        self.preferredTone = preferredTone
        self.customInstruction = customInstruction
        self.localSendCount = localSendCount
        self.sentLast30Days = sentLast30Days
        self.sentLast180Days = sentLast180Days
        self.lastSentAt = lastSentAt
    }
}

public enum FinderSelectionContext: String, Codable, Sendable {
    case selectedItems
    case currentContainer
}

public struct ComposeActionRequest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let requestID: UUID
    public let createdAt: Date
    public let recipientID: RecipientID?
    public let context: FinderSelectionContext
    public let paths: [String]

    public init(
        schemaVersion: Int = 1,
        requestID: UUID = UUID(),
        createdAt: Date = Date(),
        recipientID: RecipientID?,
        context: FinderSelectionContext,
        paths: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.createdAt = createdAt
        self.recipientID = recipientID
        self.context = context
        self.paths = paths
    }
}

public struct FinderMenuRecipient: Codable, Sendable, Equatable {
    public let recipientID: RecipientID
    public let title: String

    public init(recipientID: RecipientID, title: String) {
        self.recipientID = recipientID
        self.title = title
    }
}

public struct FinderMenuSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let menuTitle: String
    public let recipients: [FinderMenuRecipient]
    public let visibleRecipientCount: Int

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        menuTitle: String = "Envoyer par e-mail",
        recipients: [FinderMenuRecipient],
        visibleRecipientCount: Int
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.menuTitle = menuTitle
        self.recipients = recipients
        self.visibleRecipientCount = visibleRecipientCount
    }
}
