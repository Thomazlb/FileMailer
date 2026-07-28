import FileMailerDomain
import MIME
import XCTest

final class MIMETests: XCTestCase {
    func testPlainMIMEUsesCRLFAndMessageID() throws {
        let sender = try EmailAddress("sender@example.test", displayName: "Émetteur")
        let recipient = try EmailAddress("alice@example.test", displayName: "Alice")
        let message = OutboundMessage(
            id: UUID(),
            sender: sender,
            to: [recipient],
            cc: [],
            bcc: [],
            subject: "Document synthétique",
            body: "Bonjour\nTexte",
            attachments: [],
            capturedRevision: 4
        )
        let url = temporaryURL("plain.eml")
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try MIMEWriter().write(message, to: url)
        let data = try Data(contentsOf: url)
        let value = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(value.contains("\r\nMessage-ID: <"))
        XCTAssertFalse(value.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        XCTAssertEqual(result.byteCount, Int64(data.count))
    }

    func testAttachmentBase64LinesAreAtMost76Characters() throws {
        let attachmentURL = temporaryURL("payload.bin")
        try Data(repeating: 0xAB, count: 400).write(to: attachmentURL)
        defer { try? FileManager.default.removeItem(at: attachmentURL) }
        let message = OutboundMessage(
            id: UUID(),
            sender: try EmailAddress("sender@example.test"),
            to: [try EmailAddress("alice@example.test")],
            cc: [],
            bcc: [try EmailAddress("hidden@example.test")],
            subject: "Pièce jointe ünicode",
            body: "Texte",
            attachments: [
                ComposeAttachment(
                    url: attachmentURL,
                    displayName: "donnée-été.bin",
                    size: 400
                )
            ],
            capturedRevision: 1
        )
        let url = temporaryURL("attachment.eml")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try MIMEWriter().write(message, to: url)
        let value = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(value.contains("filename*=utf-8''"))
        XCTAssertTrue(value.contains("Bcc: hidden@example.test"))
        let lines = value.components(separatedBy: "\r\n")
        let base64Like = lines.filter {
            $0.count >= 4 && $0.allSatisfy { $0.isLetter || $0.isNumber || "+/=".contains($0) }
        }
        XCTAssertTrue(base64Like.allSatisfy { $0.count <= 76 })
    }

    func testHeaderInjectionIsRejected() throws {
        let message = OutboundMessage(
            id: UUID(),
            sender: try EmailAddress("sender@example.test"),
            to: [try EmailAddress("alice@example.test")],
            cc: [],
            bcc: [],
            subject: "Safe\r\nBcc: attacker@example.test",
            body: "",
            attachments: [],
            capturedRevision: 0
        )
        XCTAssertThrowsError(try MIMEWriter.validate(message))
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(name)")
    }
}
