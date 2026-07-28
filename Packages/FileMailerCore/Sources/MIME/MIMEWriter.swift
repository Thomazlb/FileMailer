import FileMailerDomain
import Foundation
import Security

public enum MIMEError: Error, LocalizedError, Sendable {
    case invalidHeader
    case attachmentUnavailable(String)
    case writeFailure

    public var errorDescription: String? {
        switch self {
        case .invalidHeader: "Un en-tête MIME est invalide."
        case let .attachmentUnavailable(name): "Impossible de lire la pièce jointe « \(name) »."
        case .writeFailure: "Impossible de créer le message MIME."
        }
    }
}

public struct MIMEBuildResult: Sendable {
    public let fileURL: URL
    public let byteCount: Int64
    public let messageID: String

    public init(fileURL: URL, byteCount: Int64, messageID: String) {
        self.fileURL = fileURL
        self.byteCount = byteCount
        self.messageID = messageID
    }
}

public struct MIMEWriter: Sendable {
    public init() {}

    public func write(
        _ message: OutboundMessage,
        to destination: URL,
        now: Date = Date()
    ) throws -> MIMEBuildResult {
        try Self.validate(message)
        let boundary = "FileMailer_\(try secureRandomHex(byteCount: 24))"
        let messageID = "<\(try secureRandomHex(byteCount: 16))@\(senderDomain(message.sender))>"
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        guard fileManager.createFile(
            atPath: destination.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw MIMEError.writeFailure
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        try writeHeader("Date", value: Self.dateString(now), to: handle)
        try writeHeader("Message-ID", value: messageID, to: handle)
        try writeHeader("From", value: addressHeader(message.sender), to: handle)
        try writeHeader("To", value: message.to.map(addressHeader).joined(separator: ", "), to: handle)
        if !message.cc.isEmpty {
            try writeHeader("Cc", value: message.cc.map(addressHeader).joined(separator: ", "), to: handle)
        }
        if !message.bcc.isEmpty {
            try writeHeader("Bcc", value: message.bcc.map(addressHeader).joined(separator: ", "), to: handle)
        }
        try writeHeader("Subject", value: encodedWordIfNeeded(message.subject), to: handle)
        try writeLine("MIME-Version: 1.0", to: handle)

        if message.attachments.isEmpty {
            try writeLine("Content-Type: text/plain; charset=utf-8", to: handle)
            try writeLine("Content-Transfer-Encoding: quoted-printable", to: handle)
            try writeLine("", to: handle)
            try writeRaw(quotedPrintable(message.body), to: handle)
            try writeRaw("\r\n", to: handle)
        } else {
            try writeLine("Content-Type: multipart/mixed; boundary=\"\(boundary)\"", to: handle)
            try writeLine("", to: handle)
            try writeLine("--\(boundary)", to: handle)
            try writeLine("Content-Type: text/plain; charset=utf-8", to: handle)
            try writeLine("Content-Transfer-Encoding: quoted-printable", to: handle)
            try writeLine("", to: handle)
            try writeRaw(quotedPrintable(message.body), to: handle)
            try writeRaw("\r\n", to: handle)

            for attachment in message.attachments {
                try writeLine("--\(boundary)", to: handle)
                let name = filenameParameters(attachment.displayName)
                try writeLine(
                    "Content-Type: \(safeContentType(attachment.contentType)); name=\"\(name.ascii)\"; name*=utf-8''\(name.encoded)",
                    to: handle
                )
                try writeLine("Content-Transfer-Encoding: base64", to: handle)
                try writeLine(
                    "Content-Disposition: attachment; filename=\"\(name.ascii)\"; filename*=utf-8''\(name.encoded)",
                    to: handle
                )
                try writeLine("", to: handle)
                try writeBase64File(attachment.url, displayName: attachment.displayName, to: handle)
            }
            try writeLine("--\(boundary)--", to: handle)
        }

        try handle.synchronize()
        let values = try destination.resourceValues(forKeys: [.fileSizeKey])
        return MIMEBuildResult(
            fileURL: destination,
            byteCount: Int64(values.fileSize ?? 0),
            messageID: messageID
        )
    }

    public static func estimatedEncodedSize(
        bodyUTF8Bytes: Int,
        attachmentBytes: Int64,
        attachmentCount: Int
    ) -> Int64 {
        let base64 = ((attachmentBytes + 2) / 3) * 4
        let lineBreaks = (base64 / 76) * 2
        return Int64(bodyUTF8Bytes) + base64 + lineBreaks + Int64(attachmentCount * 512 + 2_048)
    }

    public static func validate(_ message: OutboundMessage) throws {
        let values = [message.subject, message.sender.address]
            + message.to.map(\.address)
            + message.cc.map(\.address)
            + message.bcc.map(\.address)
        guard values.allSatisfy({
            !$0.unicodeScalars.contains(where: {
                $0.value == 0 || $0.value == 10 || $0.value == 13
            })
        }),
              !message.to.isEmpty,
              message.to.count + message.cc.count + message.bcc.count <= 50
        else {
            throw MIMEError.invalidHeader
        }
    }

    private func writeBase64File(
        _ url: URL,
        displayName: String,
        to output: FileHandle
    ) throws {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw MIMEError.attachmentUnavailable(displayName)
        }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        while true {
            let data = try input.read(upToCount: 57) ?? Data()
            if data.isEmpty { break }
            try writeLine(data.base64EncodedString(), to: output)
        }
    }

    private func writeHeader(_ name: String, value: String, to handle: FileHandle) throws {
        guard !value.unicodeScalars.contains(where: {
            $0.value == 10 || $0.value == 13
        }) else {
            throw MIMEError.invalidHeader
        }
        try writeLine("\(name): \(value)", to: handle)
    }

    private func writeLine(_ line: String, to handle: FileHandle) throws {
        try writeRaw(line + "\r\n", to: handle)
    }

    private func writeRaw(_ value: String, to handle: FileHandle) throws {
        guard let data = value.data(using: .utf8) else { throw MIMEError.writeFailure }
        try handle.write(contentsOf: data)
    }

    private func addressHeader(_ address: EmailAddress) -> String {
        guard let displayName = address.displayName, !displayName.isEmpty else {
            return address.address
        }
        return "\(encodedWordIfNeeded(displayName)) <\(address.address)>"
    }

    private func encodedWordIfNeeded(_ value: String) -> String {
        guard !value.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 32 }) else {
            return value
        }
        return "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
    }

    private func filenameParameters(_ value: String) -> (ascii: String, encoded: String) {
        let fallback = value.unicodeScalars.map { scalar -> Character in
            if scalar.isASCII, scalar.value >= 32, scalar.value != 34, scalar.value != 92 {
                return Character(scalar)
            }
            return "_"
        }
        let ascii = String(fallback).isEmpty ? "attachment" : String(fallback)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "attachment"
        return (ascii, encoded)
    }

    private func safeContentType(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$&^_.+-/")
        return value.unicodeScalars.allSatisfy(allowed.contains) ? value : "application/octet-stream"
    }

    private func quotedPrintable(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            var output = ""
            var column = 0
            for byte in line.utf8 {
                let token: String
                if (33...60).contains(byte) || (62...126).contains(byte) || byte == 9 || byte == 32 {
                    token = String(UnicodeScalar(byte))
                } else {
                    token = String(format: "=%02X", byte)
                }
                if column + token.utf8.count > 72 {
                    output += "=\r\n"
                    column = 0
                }
                output += token
                column += token.utf8.count
            }
            if output.hasSuffix(" ") {
                output.removeLast()
                output += "=20"
            } else if output.hasSuffix("\t") {
                output.removeLast()
                output += "=09"
            }
            return output
        }.joined(separator: "\r\n")
    }

    private func secureRandomHex(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw MIMEError.writeFailure
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func senderDomain(_ sender: EmailAddress) -> String {
        sender.address.split(separator: "@").last.map(String.init) ?? "localhost"
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}
