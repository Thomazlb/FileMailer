import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = AppConfiguration.baseBundleID

    static let app = Logger(subsystem: subsystem, category: "app")
    static let finderExtension = Logger(subsystem: subsystem, category: "finderExtension")
    static let ipc = Logger(subsystem: subsystem, category: "ipc")
    static let oauth = Logger(subsystem: subsystem, category: "oauth")
    static let gmail = Logger(subsystem: subsystem, category: "gmail")
    static let mime = Logger(subsystem: subsystem, category: "mime")
    static let analysis = Logger(subsystem: subsystem, category: "analysis")
    static let ai = Logger(subsystem: subsystem, category: "ai")

    static func sanitizedError(category: String, message: String) {
        let logger = switch category {
        case "ipc": ipc
        case "oauth": oauth
        case "send", "gmail": gmail
        case "mime": mime
        case "analysis": analysis
        case "ai": ai
        case "finderExtension": finderExtension
        default: app
        }
        logger.error("\(message, privacy: .private)")
    }
}
