import FileMailerDomain
import Foundation
import ZIPFoundation

struct FolderInspector: Sendable {
    static let excludedNames: Set<String> = [
        ".DS_Store", ".git", ".svn", "node_modules", "DerivedData", ".build",
        "__pycache__", ".cache"
    ]
    static let sensitiveNames: Set<String> = [
        ".env", ".ssh", ".aws", ".azure", ".config/gcloud", "id_rsa", "id_ed25519"
    ]

    func analyze(url: URL, base: Metadata, policy: AnalysisPolicy) -> AttachmentAnalysis {
        let root = url.standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return AttachmentAnalysis(
                displayName: base.name,
                contentType: "application/zip",
                size: base.size,
                deterministicSummary: "Dossier inaccessible.",
                warnings: [.inaccessible]
            )
        }
        var entries: [String] = []
        var warnings = Set<AnalysisWarning>()
        var exclusions: [String] = []
        var totalSize: Int64 = 0
        for case let item as URL in enumerator {
            if entries.count >= policy.maximumFolderEntries {
                warnings.insert(.truncated)
                break
            }
            let relative = item.path.replacingOccurrences(of: root.path + "/", with: "")
            let depth = relative.split(separator: "/").count
            if depth > policy.maximumFolderDepth {
                enumerator.skipDescendants()
                exclusions.append(relative)
                continue
            }
            if shouldExclude(item: item, relative: relative) {
                enumerator.skipDescendants()
                exclusions.append(relative)
                continue
            }
            let values = try? item.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            if values?.isSymbolicLink == true {
                let destination = item.resolvingSymlinksInPath().standardizedFileURL.path
                if destination != root.path && !destination.hasPrefix(root.path + "/") {
                    warnings.insert(.symlinkOutsideRoot)
                    exclusions.append(relative)
                    continue
                }
            }
            if isSensitive(item: item, relative: relative) {
                warnings.insert(.sensitiveFile)
            }
            entries.append(relative)
            totalSize += Int64(values?.fileSize ?? 0)
        }
        let exclusionSummary = exclusions.isEmpty
            ? ""
            : " \(exclusions.count) éléments exclus par défaut."
        return AttachmentAnalysis(
            displayName: base.name,
            contentType: "application/zip",
            size: totalSize,
            creationDate: base.creationDate,
            modificationDate: base.modificationDate,
            deterministicSummary: "Dossier à compresser en ZIP, \(entries.count) entrées.\(exclusionSummary)",
            warnings: warnings
        )
    }

    func shouldExclude(item: URL, relative: String) -> Bool {
        let components = relative.split(separator: "/").map(String.init)
        return item.lastPathComponent.hasPrefix(".")
            || components.contains(where: Self.excludedNames.contains)
    }

    func isSensitive(item: URL, relative: String) -> Bool {
        let lower = relative.lowercased()
        let name = item.lastPathComponent.lowercased()
        return Self.sensitiveNames.contains(name)
            || lower.contains("/.ssh/")
            || ["pem", "p12", "keychain", "keychain-db"].contains(item.pathExtension.lowercased())
            || name.contains("credentials")
    }
}

public struct FolderArchiveManifest: Sendable {
    public let archivedCount: Int
    public let excludedPaths: [String]
    public let sensitivePaths: [String]

    public init(archivedCount: Int, excludedPaths: [String], sensitivePaths: [String]) {
        self.archivedCount = archivedCount
        self.excludedPaths = excludedPaths
        self.sensitivePaths = sensitivePaths
    }
}

public actor FolderArchiver {
    public init() {}

    public func archive(
        folder: URL,
        to destination: URL,
        allowSensitiveFiles: Bool = false
    ) throws -> FolderArchiveManifest {
        let root = folder.standardizedFileURL
        let inspector = FolderInspector()
        let archive = try Archive(url: destination, accessMode: .create)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw FileAnalysisError.folderTooLarge
        }
        var archived = 0
        var excluded: [String] = []
        var sensitive: [String] = []
        for case let item as URL in enumerator {
            try Task.checkCancellation()
            let relative = item.path.replacingOccurrences(of: root.path + "/", with: "")
            if inspector.shouldExclude(item: item, relative: relative) {
                enumerator.skipDescendants()
                excluded.append(relative)
                continue
            }
            let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                excluded.append(relative)
                continue
            }
            if inspector.isSensitive(item: item, relative: relative) {
                sensitive.append(relative)
                if !allowSensitiveFiles {
                    excluded.append(relative)
                    continue
                }
            }
            try archive.addEntry(with: relative, relativeTo: root)
            archived += 1
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
        return FolderArchiveManifest(
            archivedCount: archived,
            excludedPaths: excluded,
            sensitivePaths: sensitive
        )
    }
}
