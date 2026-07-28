import Foundation

@MainActor
final class DriveCleanupScheduler {
    private let scheduler: NSBackgroundActivityScheduler
    private let clean: @MainActor @Sendable () async -> Void

    init(
        identifier: String,
        clean: @escaping @MainActor @Sendable () async -> Void
    ) {
        scheduler = NSBackgroundActivityScheduler(identifier: identifier)
        self.clean = clean
        scheduler.repeats = true
        scheduler.interval = 60 * 60
        scheduler.tolerance = 15 * 60
    }

    func start() {
        let clean = clean
        scheduler.schedule { completion in
            Task { @MainActor in
                await clean()
                completion(.finished)
            }
        }
    }
}
