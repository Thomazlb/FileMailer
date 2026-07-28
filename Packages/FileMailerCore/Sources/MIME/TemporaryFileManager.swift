import FileMailerDomain
import Foundation

public actor TemporaryFileManager: TemporaryFileManaging {
    private let root: URL
    private var registered = Set<URL>()

    public init(baseURL: URL? = nil) throws {
        let cache = baseURL ?? FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!
        root = cache.appendingPathComponent("FileMailer/Temporary", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = root
        try mutableRoot.setResourceValues(values)
    }

    public func makeTemporaryFile(extension fileExtension: String?) throws -> URL {
        let suffix = fileExtension.map { ".\($0)" } ?? ""
        let url = root.appendingPathComponent(UUID().uuidString + suffix)
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        registered.insert(url)
        return url
    }

    public func register(_ url: URL) {
        registered.insert(url)
    }

    public func remove(_ url: URL) {
        guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            return
        }
        try? FileManager.default.removeItem(at: url)
        registered.remove(url)
    }

    public func cleanExpiredFiles(olderThan interval: TimeInterval = 86_400) {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-interval)
        for child in children {
            let modified = try? child.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            if (modified ?? .distantPast) < cutoff {
                try? FileManager.default.removeItem(at: child)
                registered.remove(child)
            }
        }
    }

    public func removeAllRegistered() {
        for url in registered {
            try? FileManager.default.removeItem(at: url)
        }
        registered.removeAll()
    }
}
