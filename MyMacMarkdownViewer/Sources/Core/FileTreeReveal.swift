import Foundation

public enum FileTreeReveal {
    public struct Snapshot: Sendable {
        public let target: URL
        public let directories: [URL]
        public let entries: [String: [FileEntry]]
    }

    /// Only the root and the target's ancestors are needed, not a recursive index.
    public static func directories(for document: URL, inside root: URL) -> [URL]? {
        guard document.isFileURL, root.isFileURL else { return nil }
        let target = document.standardizedFileURL, root = root.standardizedFileURL
        let rootParts = root.pathComponents, targetParts = target.pathComponents
        guard targetParts.count > rootParts.count,
              Array(targetParts.prefix(rootParts.count)) == rootParts else { return nil }
        var directories = [root]
        for component in targetParts.dropFirst(rootParts.count).dropLast() {
            directories.append(directories.last!.appendingPathComponent(component, isDirectory: true))
        }
        return directories
    }

    public static func read(document: URL, inside root: URL) throws -> Snapshot {
        guard let directories = directories(for: document, inside: root) else { throw CocoaError(.fileReadNoPermission) }
        let target = document.standardizedFileURL
        var entries: [String: [FileEntry]] = [:]
        var scannedDirectories: [URL] = []
        var directory = directories[0]
        var foundTarget = target
        let names = directories.dropFirst().map(\.lastPathComponent) + [target.lastPathComponent]
        for (index, name) in names.enumerated() {
            try Task.checkCancellation()
            let listing = try FolderScanner.children(of: directory)
            let expectsDirectory = index + 1 < names.count
            guard let next = listing.first(where: { $0.name == name && $0.isDirectory == expectsDirectory }) else {
                // A hidden, deleted or excluded/symlinked item is not a tree row.
                throw CocoaError(.fileReadNoSuchFile)
            }
            scannedDirectories.append(directory)
            entries[directory.path] = listing
            // Foundation may return canonical paths (e.g. /private/var for
            // /var). Follow the row's actual URL so expansion IDs still match.
            if expectsDirectory { directory = next.url } else { foundTarget = next.url }
        }
        return Snapshot(target: foundTarget, directories: scannedDirectories, entries: entries)
    }
}
