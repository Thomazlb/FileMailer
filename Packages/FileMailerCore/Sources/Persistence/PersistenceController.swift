import FileMailerDomain
import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
public final class PersistenceController {
    public let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: FileMailerSchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(
                "FileMailer",
                schema: schema,
                isStoredInMemoryOnly: true
            )
        } else {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = applicationSupport
                .appendingPathComponent("FileMailer", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            configuration = ModelConfiguration(
                "FileMailer",
                schema: schema,
                url: directory.appendingPathComponent("FileMailer.store")
            )
        }
        container = try ModelContainer(
            for: schema,
            migrationPlan: FileMailerMigrationPlan.self,
            configurations: configuration
        )
    }

    public func recipients() throws -> [RecipientProfile] {
        let values = try context.fetch(FetchDescriptor<StoredRecipient>())
            .map { $0.domainValue }
        return values.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.pinOrder != $1.pinOrder {
                return ($0.pinOrder ?? .max) < ($1.pinOrder ?? .max)
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    public func upsert(recipient: RecipientProfile) throws {
        let id = recipient.id.rawValue
        let descriptor = FetchDescriptor<StoredRecipient>(
            predicate: #Predicate { $0.uuid == id }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.update(from: recipient)
        } else {
            context.insert(StoredRecipient(recipient))
        }
        try context.save()
    }

    public func delete(recipientID: RecipientID) throws {
        let id = recipientID.rawValue
        let descriptor = FetchDescriptor<StoredRecipient>(
            predicate: #Predicate { $0.uuid == id }
        )
        for value in try context.fetch(descriptor) {
            context.delete(value)
        }
        try context.save()
    }

    public func accounts() throws -> [GmailAccountSummary] {
        let values = try context.fetch(FetchDescriptor<StoredGmailAccountMetadata>())
            .sorted { $0.sortOrder < $1.sortOrder }
        return values.map { $0.domainValue }
    }

    public func upsert(account: GmailAccountSummary) throws {
        let subject = account.id.rawValue
        let descriptor = FetchDescriptor<StoredGmailAccountMetadata>(
            predicate: #Predicate { $0.subject == subject }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.email = account.email
            existing.displayName = account.displayName
            existing.isDefault = account.isDefault
            existing.lastUsedAt = account.lastUsedAt
            existing.grantedScopes = account.grantedScopes.sorted()
            existing.authStatusRaw = account.authStatus.rawValue
            existing.signature = account.signature
        } else {
            context.insert(StoredGmailAccountMetadata(account))
        }
        if account.isDefault {
            for stored in try context.fetch(FetchDescriptor<StoredGmailAccountMetadata>())
                where stored.subject != subject {
                stored.isDefault = false
            }
        }
        try context.save()
    }

    public func removeAccountMetadata(accountID: GmailAccountID) throws {
        let subject = accountID.rawValue
        let accounts = try context.fetch(
            FetchDescriptor<StoredGmailAccountMetadata>(
                predicate: #Predicate { $0.subject == subject }
            )
        )
        for account in accounts { context.delete(account) }
        let recipients = try context.fetch(FetchDescriptor<StoredRecipient>())
        for recipient in recipients where recipient.preferredSenderSubject == subject {
            recipient.preferredSenderSubject = nil
        }
        try context.save()
    }

    public func settings() throws -> StoredAppSettings {
        let descriptor = FetchDescriptor<StoredAppSettings>(
            predicate: #Predicate { $0.key == "settings" }
        )
        if let settings = try context.fetch(descriptor).first { return settings }
        let settings = StoredAppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }

    public func recordSuccessfulSend(
        accountID: GmailAccountID,
        recipients: [EmailAddress],
        attachments: [ComposeAttachment],
        now: Date = Date()
    ) throws {
        let totalSize = attachments.reduce(Int64(0)) { $0 + $1.size }
        let categories = Array(Set(attachments.map {
            $0.contentType.split(separator: "/").first.map(String.init) ?? "other"
        })).sorted()
        for recipient in recipients {
            context.insert(
                StoredSendEvent(
                    timestamp: now,
                    accountID: accountID,
                    normalizedRecipient: recipient.normalized,
                    attachmentCount: attachments.count,
                    totalSize: totalSize,
                    contentCategories: categories,
                    succeeded: true
                )
            )
            let normalized = recipient.normalized
            let descriptor = FetchDescriptor<StoredRecipient>(
                predicate: #Predicate { $0.normalizedEmail == normalized }
            )
            if let stored = try context.fetch(descriptor).first {
                stored.localSendCount += 1
                stored.sentLast30Days += 1
                stored.sentLast180Days += 1
                stored.lastSentAt = now
            }
        }
        try context.save()
    }

    public func savePendingDraft(_ draft: ComposeDraft, now: Date = Date()) throws {
        let descriptor = FetchDescriptor<StoredPendingDraft>(
            predicate: #Predicate { $0.id == draft.id }
        )
        let bookmarks = draft.attachments.compactMap {
            try? $0.url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        let stored: StoredPendingDraft
        if let existing = try context.fetch(descriptor).first {
            stored = existing
            stored.senderSubject = draft.senderID?.rawValue
            stored.toAddresses = draft.to.map(\.address)
            stored.ccAddresses = draft.cc.map(\.address)
            stored.bccAddresses = draft.bcc.map(\.address)
            stored.subject = draft.subject
            stored.body = draft.body
            stored.attachmentBookmarks = bookmarks
            stored.updatedAt = now
        } else {
            stored = StoredPendingDraft(
                id: draft.id,
                senderSubject: draft.senderID?.rawValue,
                toAddresses: draft.to.map(\.address),
                ccAddresses: draft.cc.map(\.address),
                bccAddresses: draft.bcc.map(\.address),
                subject: draft.subject,
                body: draft.body,
                attachmentBookmarks: bookmarks,
                updatedAt: now
            )
            context.insert(stored)
        }
        try context.save()
    }

    public func pendingDrafts() throws -> [ComposeDraft] {
        let stored = try context.fetch(FetchDescriptor<StoredPendingDraft>())
            .sorted { $0.updatedAt > $1.updatedAt }
        return stored.map { value in
            var stale = false
            let attachments = value.attachmentBookmarks.compactMap { data -> ComposeAttachment? in
                guard let url = try? URL(
                    resolvingBookmarkData: data,
                    options: [.withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) else {
                    return nil
                }
                let values = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .contentTypeKey, .contentModificationDateKey]
                )
                return ComposeAttachment(
                    url: url,
                    contentType: values?.contentType?.preferredMIMEType
                        ?? "application/octet-stream",
                    size: Int64(values?.fileSize ?? 0),
                    modificationDate: values?.contentModificationDate
                )
            }
            return ComposeDraft(
                id: value.id,
                senderID: value.senderSubject.map(GmailAccountID.init(rawValue:)),
                to: value.toAddresses.compactMap { try? EmailAddress($0) },
                cc: value.ccAddresses.compactMap { try? EmailAddress($0) },
                bcc: value.bccAddresses.compactMap { try? EmailAddress($0) },
                subject: value.subject,
                body: value.body,
                attachments: attachments,
                generationState: .manual
            )
        }
    }

    public func deletePendingDraft(id: UUID) throws {
        let descriptor = FetchDescriptor<StoredPendingDraft>(
            predicate: #Predicate { $0.id == id }
        )
        for draft in try context.fetch(descriptor) {
            context.delete(draft)
        }
        try context.save()
    }

    public func deleteAllPendingDrafts() throws {
        for draft in try context.fetch(FetchDescriptor<StoredPendingDraft>()) {
            context.delete(draft)
        }
        try context.save()
    }
}
