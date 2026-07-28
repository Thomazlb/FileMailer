import FileMailerDomain
import RecipientRanking
import XCTest

final class DomainAndRankingTests: XCTestCase {
    func testPinnedRecipientsLeadInManualOrder() {
        let now = Date(timeIntervalSince1970: 10_000)
        let pinnedSecond = RecipientProfile(
            displayName: "Second",
            email: "second@example.test",
            isPinned: true,
            pinOrder: 1
        )
        let pinnedFirst = RecipientProfile(
            displayName: "First",
            email: "first@example.test",
            isPinned: true,
            pinOrder: 0
        )
        let frequent = RecipientProfile(
            displayName: "Frequent",
            email: "frequent@example.test",
            localSendCount: 100,
            sentLast30Days: 20,
            lastSentAt: now
        )
        let result = DefaultRecipientRanker().ranked(
            recipients: [frequent, pinnedSecond, pinnedFirst],
            excludingOwnAddresses: [],
            limit: 5,
            now: now
        )
        XCTAssertEqual(result.map(\.displayName), ["First", "Second", "Frequent"])
    }

    func testRankingLimitAndAutomatedAddressExclusion() {
        let values = (0..<25).map {
            RecipientProfile(
                displayName: "Person \($0)",
                email: "person\($0)@example.test",
                localSendCount: $0
            )
        } + [
            RecipientProfile(displayName: "Robot", email: "no-reply@example.test")
        ]
        let result = DefaultRecipientRanker().ranked(
            recipients: values,
            excludingOwnAddresses: [],
            limit: 40,
            now: Date()
        )
        XCTAssertEqual(result.count, 20)
        XCTAssertFalse(result.contains { $0.displayName == "Robot" })
    }

    func testEmailNormalizationIsConservative() throws {
        let address = try EmailAddress("  User.Name+tag@EXAMPLE.COM ")
        XCTAssertEqual(address.normalized, "user.name+tag@example.com")
        XCTAssertTrue(address.normalized.contains("+tag"))
        XCTAssertTrue(address.normalized.contains("."))
    }

    func testInvalidAddressesAndHeaderInjectionAreRejected() {
        XCTAssertThrowsError(try EmailAddress("invalid"))
        XCTAssertThrowsError(try EmailAddress("victim@example.test\r\nBcc: attacker@example.test")) {
            XCTAssertEqual($0 as? EmailAddressError, .headerInjection)
        }
    }

    func testSnapshotContainsNoAccountOrTokenData() throws {
        let recipient = RecipientProfile(
            displayName: "Alice",
            email: "alice@example.test",
            preferredSenderID: GmailAccountID(rawValue: "oidc-subject")
        )
        let snapshot = FinderSnapshotBuilder().makeSnapshot(
            recipients: [recipient],
            ownAddresses: [],
            visibleCount: 5,
            now: Date()
        )
        let data = try JSONEncoder().encode(snapshot)
        let string = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(string.contains("oidc-subject"))
        XCTAssertFalse(string.contains("access_token"))
        XCTAssertFalse(string.contains("alice@example.test"))
    }
}
