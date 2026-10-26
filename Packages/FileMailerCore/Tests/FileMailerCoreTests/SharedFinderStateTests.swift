import FileMailerDomain
import FileMailerIPC
import Foundation
import XCTest

final class SharedFinderStateTests: XCTestCase {
    private func temporaryContainer() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testSnapshotSurvivesReopeningAndPreservesLanguage() throws {
        let root = try temporaryContainer()
        let store = SharedFinderStateStore(containerURL: root)
        XCTAssertNil(try store.loadSnapshot())
        let snapshot = FinderMenuSnapshot(recipients: [], visibleRecipientCount: 5, languageIdentifier: "ja")
        try store.saveSnapshot(snapshot)
        let reopened = SharedFinderStateStore(containerURL: root)
        XCTAssertEqual(try reopened.loadSnapshot()?.languageIdentifier, "ja")
        XCTAssertEqual(try reopened.loadSnapshot()?.visibleRecipientCount, 5)
    }

    func testActionIsConsumedOnceAndURLContainsOnlyItsIdentifier() throws {
        let store = SharedFinderStateStore(containerURL: try temporaryContainer())
        let request = ComposeActionRequest(recipientID: nil, context: .selectedItems, paths: ["/tmp/private name.pdf"])
        try store.saveAction(IPCActionEnvelope(request: request, command: nil))
        let codec = IPCActionURLCodec()
        let url = codec.referenceURL(requestID: request.requestID)
        XCTAssertFalse(url.absoluteString.contains("private"))
        XCTAssertFalse(url.absoluteString.contains("payload"))
        XCTAssertEqual(codec.referenceID(from: url), request.requestID)
        XCTAssertEqual(try store.takeAction(id: request.requestID).request.paths, request.paths)
        XCTAssertThrowsError(try store.takeAction(id: request.requestID))
        XCTAssertNil(codec.referenceID(from: URL(string: url.absoluteString + "&request=" + UUID().uuidString)!))
        XCTAssertNil(codec.referenceID(from: URL(string: "https://action?request=" + request.requestID.uuidString)!))
    }

    func testExpiredRequestsAndUnknownCommandsAreRejected() throws {
        let store = SharedFinderStateStore(containerURL: try temporaryContainer())
        let now = Date()
        let request = ComposeActionRequest(createdAt: now, recipientID: nil, context: .selectedItems, paths: ["/tmp/file"])
        XCTAssertThrowsError(try store.saveAction(IPCActionEnvelope(request: request, command: "send"), now: now))
        try store.saveAction(IPCActionEnvelope(request: request, command: "openApp"), now: now)
        XCTAssertThrowsError(try store.takeAction(id: request.requestID, now: now.addingTimeInterval(31))) {
            XCTAssertEqual($0 as? IPCError, .expiredAction)
        }
        let relative = ComposeActionRequest(recipientID: nil, context: .selectedItems, paths: ["../file"])
        XCTAssertThrowsError(try store.saveAction(IPCActionEnvelope(request: relative, command: nil))) {
            XCTAssertEqual($0 as? IPCError, .invalidPath)
        }
    }

    func testSnapshotRejectsInvalidMenuCountAndOversizedFiles() throws {
        let root = try temporaryContainer()
        let store = SharedFinderStateStore(containerURL: root)
        XCTAssertThrowsError(try store.saveSnapshot(FinderMenuSnapshot(recipients: [], visibleRecipientCount: -1)))
        let snapshot = FinderMenuSnapshot(recipients: [], visibleRecipientCount: 5)
        try store.saveSnapshot(snapshot)
        let url = root.appendingPathComponent("FinderState/snapshot.json")
        try Data(repeating: 0, count: IPCPayloadLimit.snapshot.rawValue + 1).write(to: url)
        XCTAssertThrowsError(try store.loadSnapshot()) {
            XCTAssertEqual($0 as? IPCError, .payloadTooLarge)
        }
    }

    func testSnapshotRejectsSymbolicLinks() throws {
        let root = try temporaryContainer()
        let store = SharedFinderStateStore(containerURL: root)
        try store.saveSnapshot(FinderMenuSnapshot(recipients: [], visibleRecipientCount: 5))
        let url = root.appendingPathComponent("FinderState/snapshot.json")
        let other = root.appendingPathComponent("other.json")
        try FileManager.default.moveItem(at: url, to: other)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: other)
        XCTAssertThrowsError(try store.loadSnapshot())
    }

    func testExpiredQueueEntriesArePrunedBeforeCheckingCapacity() throws {
        let root = try temporaryContainer()
        let store = SharedFinderStateStore(containerURL: root)
        let now = Date()
        for _ in 0..<100 {
            let request = ComposeActionRequest(createdAt: now, recipientID: nil, context: .selectedItems, paths: ["/tmp/file"])
            try store.saveAction(IPCActionEnvelope(request: request, command: nil), now: now)
        }
        let fresh = ComposeActionRequest(createdAt: now, recipientID: nil, context: .selectedItems, paths: ["/tmp/fresh"])
        XCTAssertThrowsError(try store.saveAction(IPCActionEnvelope(request: fresh, command: nil), now: now))
        let later = now.addingTimeInterval(70)
        let request = ComposeActionRequest(createdAt: later, recipientID: nil, context: .selectedItems, paths: ["/tmp/fresh"])
        try store.saveAction(IPCActionEnvelope(request: request, command: nil), now: later)
        XCTAssertEqual(try store.takeAction(id: request.requestID, now: later).request.paths, ["/tmp/fresh"])
    }
}
