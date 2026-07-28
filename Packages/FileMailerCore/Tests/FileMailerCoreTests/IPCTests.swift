import FileMailerDomain
import FileMailerIPC
import XCTest

final class IPCTests: XCTestCase {
    func testChunkingAndChecksumRoundTrip() throws {
        let paths = (0..<50).map { "/tmp/" + String(repeating: "a", count: 2_000) + "\($0)" }
        let request = ComposeActionRequest(
            recipientID: nil,
            context: .selectedItems,
            paths: paths
        )
        let codec = IPCCodec()
        let chunks = try codec.encode(request, limit: .action)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertLessThanOrEqual(chunks.count, 64)
        let decoded = try codec.decode(
            ComposeActionRequest.self,
            from: chunks.reversed(),
            limit: .action
        )
        XCTAssertEqual(decoded.schemaVersion, request.schemaVersion)
        XCTAssertEqual(decoded.requestID, request.requestID)
        XCTAssertEqual(decoded.recipientID, request.recipientID)
        XCTAssertEqual(decoded.context, request.context)
        XCTAssertEqual(decoded.paths, request.paths)
        XCTAssertEqual(
            decoded.createdAt.timeIntervalSince1970,
            request.createdAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testChecksumMismatchIsRejected() throws {
        let request = ComposeActionRequest(
            recipientID: nil,
            context: .selectedItems,
            paths: ["/tmp/file"]
        )
        let codec = IPCCodec()
        var chunks = try codec.encode(request, limit: .action)
        let original = chunks[0]
        chunks[0] = IPCChunk(
            messageID: original.messageID,
            index: original.index,
            count: original.count,
            sha256: String(repeating: "0", count: 64),
            payloadBase64: original.payloadBase64
        )
        XCTAssertThrowsError(
            try codec.decode(ComposeActionRequest.self, from: chunks, limit: .action)
        ) {
            XCTAssertEqual($0 as? IPCError, .checksumMismatch)
        }
    }

    func testOversizedPayloadIsRejected() {
        let request = ComposeActionRequest(
            recipientID: nil,
            context: .selectedItems,
            paths: [String(repeating: "x", count: 140_000)]
        )
        XCTAssertThrowsError(try IPCCodec().encode(request, limit: .action)) {
            XCTAssertEqual($0 as? IPCError, .payloadTooLarge)
        }
    }

    func testExpiredAndInvalidPathsAreRejected() {
        let validator = ComposeActionValidator()
        let old = ComposeActionRequest(
            createdAt: Date(timeIntervalSinceNow: -31),
            recipientID: nil,
            context: .selectedItems,
            paths: ["/tmp/file"]
        )
        XCTAssertThrowsError(try validator.validate(old, now: Date())) {
            XCTAssertEqual($0 as? IPCError, .expiredAction)
        }
        let invalid = ComposeActionRequest(
            recipientID: nil,
            context: .selectedItems,
            paths: ["/tmp/file\0"]
        )
        XCTAssertThrowsError(try validator.validate(invalid, now: Date())) {
            XCTAssertEqual($0 as? IPCError, .invalidPath)
        }
    }

    func testDuplicateRequestIsRejected() async throws {
        let value = UUID()
        let deduplicator = RequestDeduplicator()
        try await deduplicator.accept(value, now: Date())
        do {
            try await deduplicator.accept(value, now: Date())
            XCTFail("Duplicate request should fail")
        } catch {
            XCTAssertEqual(error as? IPCError, .duplicateRequest)
        }
    }

    func testReassemblyCompletesOnlyWithAllChunks() async throws {
        let codec = IPCCodec()
        let request = ComposeActionRequest(
            recipientID: nil,
            context: .selectedItems,
            paths: [String(repeating: "x", count: 90_000)]
        )
        let chunks = try codec.encode(request, limit: .action)
        let reassembler = IPCChunkReassembler()
        for chunk in chunks.dropLast() {
            let result = try await reassembler.ingest(chunk)
            XCTAssertNil(result)
        }
        let complete = try await reassembler.ingest(chunks.last!)
        XCTAssertEqual(complete?.count, chunks.count)
    }
}
