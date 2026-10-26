import Foundation

/// Keep this lease alive for the entire analysis, upload and send operation.
/// Only successful starts are balanced by a stop; container-local URLs need none.
public final class SecurityScopedFileAccess: Sendable {
    private let activeURLs: [URL]

    public init(urls: [URL]) {
        var seen = Set<URL>()
        activeURLs = urls.filter { seen.insert($0).inserted && $0.startAccessingSecurityScopedResource() }
    }

    deinit {
        activeURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }
}
