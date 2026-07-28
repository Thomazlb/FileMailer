import FileMailerDomain
import Foundation

public struct DefaultRecipientRanker: FileMailerDomain.RecipientRanking {
    public init() {}

    public func score(_ recipient: RecipientProfile, now: Date) -> Double {
        let days: Double
        if let lastSentAt = recipient.lastSentAt {
            days = max(0, now.timeIntervalSince(lastSentAt) / 86_400)
        } else {
            days = 365
        }
        return 4.0 * exp(-days / 21.0)
            + 2.0 * log1p(Double(recipient.sentLast30Days))
            + log1p(Double(recipient.sentLast180Days))
            + 0.5 * log1p(Double(recipient.localSendCount))
    }

    public func ranked(
        recipients: [RecipientProfile],
        excludingOwnAddresses: Set<String>,
        limit: Int,
        now: Date
    ) -> [RecipientProfile] {
        let own = Set(excludingOwnAddresses.map(EmailAddress.normalized))
        let boundedLimit = min(max(limit, 1), 20)
        var seen = Set<String>()

        let eligible = recipients.filter { recipient in
            guard recipient.isEnabled else { return false }
            let normalized = EmailAddress.normalized(recipient.normalizedEmail)
            guard !own.contains(normalized), !Self.isAutomatedAddress(normalized) else {
                return false
            }
            return seen.insert(normalized).inserted
        }

        let pinned = eligible
            .filter(\.isPinned)
            .sorted {
                let left = $0.pinOrder ?? .max
                let right = $1.pinOrder ?? .max
                if left != right { return left < right }
                return Self.tieBreak($0, $1)
            }

        let unpinned = eligible
            .filter { !$0.isPinned }
            .sorted {
                let left = score($0, now: now)
                let right = score($1, now: now)
                if left != right { return left > right }
                if $0.lastSentAt != $1.lastSentAt {
                    return ($0.lastSentAt ?? .distantPast) > ($1.lastSentAt ?? .distantPast)
                }
                return Self.tieBreak($0, $1)
            }

        return Array((pinned + unpinned).prefix(boundedLimit))
    }

    private static func isAutomatedAddress(_ email: String) -> Bool {
        guard let local = email.split(separator: "@").first else { return false }
        let compact = local
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
        return compact == "noreply" || compact == "donotreply"
    }

    private static func tieBreak(_ left: RecipientProfile, _ right: RecipientProfile) -> Bool {
        let nameComparison = left.displayName.localizedStandardCompare(right.displayName)
        if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
        return left.normalizedEmail.localizedStandardCompare(right.normalizedEmail) == .orderedAscending
    }
}

public struct FinderSnapshotBuilder: Sendable {
    private let ranker: DefaultRecipientRanker

    public init(ranker: DefaultRecipientRanker = DefaultRecipientRanker()) {
        self.ranker = ranker
    }

    public func makeSnapshot(
        recipients: [RecipientProfile],
        ownAddresses: Set<String>,
        visibleCount: Int,
        now: Date
    ) -> FinderMenuSnapshot {
        let ranked = ranker.ranked(
            recipients: recipients,
            excludingOwnAddresses: ownAddresses,
            limit: visibleCount,
            now: now
        )
        return FinderMenuSnapshot(
            generatedAt: now,
            recipients: ranked.map {
                FinderMenuRecipient(
                    recipientID: $0.id,
                    title: $0.displayName.isEmpty ? $0.email : $0.displayName
                )
            },
            visibleRecipientCount: min(max(visibleCount, 1), 10)
        )
    }
}
