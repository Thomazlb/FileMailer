import AppKit
import FileMailerCore
import Foundation

/// Read-only grants are created only from URLs selected or opened by the user.
/// Finder paths are requests, not permission to read the corresponding files.
@MainActor
final class FileAccessController {
    struct Selection {
        let urls: [URL]
        let leases: [SecurityScopedFileAccess]
    }

    private let storageURL: URL?
    private var bookmarks: [String: Data]

    init(inMemory: Bool, storeName: String = "FileAccess") {
        storageURL = inMemory ? nil : FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.appendingPathComponent("FileMailer", isDirectory: true)
            .appendingPathComponent(storeName).appendingPathExtension("json")
        bookmarks = storageURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) } ?? [:]
    }

    func userSelected(_ urls: [URL]) throws -> Selection {
        let urls = Array(urls.filter(\.isFileURL).prefix(50))
        let lease = SecurityScopedFileAccess(urls: urls)
        for url in urls {
            // A failure must be visible rather than silently losing an attachment on relaunch.
            bookmarks[url.standardizedFileURL.path] = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil, relativeTo: nil
            )
        }
        if bookmarks.count > 200 {
            let selectedPaths = Set(urls.map { $0.standardizedFileURL.path })
            for key in bookmarks.keys.sorted() where bookmarks.count > 200 && !selectedPaths.contains(key) {
                bookmarks.removeValue(forKey: key)
            }
        }
        if let storageURL {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(bookmarks).write(to: storageURL, options: .atomic)
        }
        return Selection(urls: urls, leases: [lease])
    }

    func finderSelection(paths: [String], localization: FileMailerLocalization) throws -> Selection? {
        let urls = paths.prefix(50).map { URL(fileURLWithPath: $0) }
        var grants: [URL] = []
        for (path, data) in bookmarks where urls.contains(where: {
            let requested = $0.standardizedFileURL.path
            return requested == path || requested.hasPrefix(path.hasSuffix("/") ? path : path + "/")
        }) {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                relativeTo: nil, bookmarkDataIsStale: &stale
            ) else { continue }
            grants.append(url)
        }
        var leases = [SecurityScopedFileAccess(urls: grants)]
        if let inaccessible = urls.first(where: { !Self.isReadable($0) }) {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.directoryURL = inaccessible.deletingLastPathComponent()
            panel.nameFieldStringValue = inaccessible.lastPathComponent
            panel.message = localization.string("File inaccessible. Select it again.")
            panel.prompt = localization.string("Add")
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK else { return nil }
            let selection = try userSelected(panel.urls)
            leases.append(contentsOf: selection.leases)
            guard urls.allSatisfy(Self.isReadable) else {
                throw FileAccessError.inaccessible(localization.string("File inaccessible. Select it again."))
            }
        }
        return Selection(urls: Array(urls), leases: leases)
    }

    private static func isReadable(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isReadableKey]).isReadable) == true
            && FileManager.default.isReadableFile(atPath: url.path)
    }
}

private enum FileAccessError: LocalizedError {
    case inaccessible(String)
    var errorDescription: String? {
        switch self { case .inaccessible(let message): message }
    }
}
