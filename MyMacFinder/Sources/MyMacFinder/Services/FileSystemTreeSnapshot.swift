import CryptoKit
import Darwin
import Foundation

struct FileSystemTreeSnapshot: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var identity: FileSystemPathIdentity.FileSystemEntryIdentity
        var metadata: Metadata
        var contentDigest: Data?
        var symbolicLinkDestination: String?
    }

    struct Metadata: Equatable, Sendable {
        var size: Int64
        var modificationSeconds: Int64
        var modificationNanoseconds: Int64
        var changeSeconds: Int64
        var changeNanoseconds: Int64
    }

    var entries: [String: Entry]

    var rootIdentity: FileSystemPathIdentity.FileSystemEntryIdentity? {
        entries[""]?.identity
    }

    static func capture(
        at rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> FileSystemTreeSnapshot {
        let root = rootURL.standardizedFileURL
        guard FileSystemPathIdentity.entryExists(root) else {
            throw ExplorerError.operationFailed("Filesystem snapshot root is missing: \(root.path)")
        }

        var result: [String: Entry] = [:]
        var pending = [root]
        var cursor = 0

        while cursor < pending.count {
            let url = pending[cursor]
            cursor += 1
            let key = relativePath(for: url, root: root)
            let beforeMetadata = try metadata(for: url)
            guard let identity = FileSystemPathIdentity.entryIdentity(url) else {
                throw ExplorerError.operationFailed("Filesystem entry changed during snapshot: \(url.path)")
            }

            let fileType = identity.mode & UInt32(S_IFMT)
            let contentDigest: Data?
            let symbolicLinkDestination: String?
            switch fileType {
            case UInt32(S_IFREG):
                contentDigest = try digest(of: url)
                symbolicLinkDestination = nil
            case UInt32(S_IFLNK):
                contentDigest = nil
                symbolicLinkDestination = try fileManager.destinationOfSymbolicLink(atPath: url.path)
            default:
                contentDigest = nil
                symbolicLinkDestination = nil
            }

            let children: [URL]
            if fileType == UInt32(S_IFDIR) {
                children = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: []
                )
            } else {
                children = []
            }

            guard FileSystemPathIdentity.entryIdentity(url) == identity,
                  try metadata(for: url) == beforeMetadata else {
                throw ExplorerError.operationFailed("Filesystem entry changed during snapshot: \(url.path)")
            }
            result[key] = Entry(
                identity: identity,
                metadata: beforeMetadata,
                contentDigest: contentDigest,
                symbolicLinkDestination: symbolicLinkDestination
            )
            pending.append(contentsOf: children.map(\.standardizedFileURL))
        }

        return FileSystemTreeSnapshot(entries: result)
    }

    func rebasingRootMetadata(at rootURL: URL) throws -> FileSystemTreeSnapshot {
        guard var rootEntry = entries[""] else {
            throw ExplorerError.operationFailed(
                "Filesystem snapshot root identity is unavailable: \(rootURL.path)"
            )
        }
        rootEntry.metadata = try Self.metadata(for: rootURL.standardizedFileURL)
        var rebasedEntries = entries
        rebasedEntries[""] = rootEntry
        return FileSystemTreeSnapshot(entries: rebasedEntries)
    }

    func matchesIgnoringRelocationMetadata(of other: FileSystemTreeSnapshot) -> Bool {
        guard var lhsRoot = entries[""],
              let rhsRoot = other.entries[""] else {
            return false
        }
        lhsRoot.metadata = rhsRoot.metadata
        var normalizedEntries = entries
        normalizedEntries[""] = lhsRoot
        return normalizedEntries == other.entries
    }

    static func quarantineAndRemoveIfUnchanged(
        at url: URL,
        expectedSnapshot: FileSystemTreeSnapshot,
        fileManager: FileManager = .default
    ) throws {
        let original = url.standardizedFileURL
        guard let expectedIdentity = expectedSnapshot.rootIdentity else {
            throw ExplorerError.operationFailed(
                "Rollback ownership is unavailable: \(original.path)"
            )
        }

        let quarantineDirectory = uniqueQuarantineDirectory(nextTo: original)
        try fileManager.createDirectory(
            at: quarantineDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        guard let quarantineDirectoryIdentity = FileSystemPathIdentity.entryIdentity(quarantineDirectory) else {
            throw ExplorerError.operationFailed(
                "Rollback quarantine identity is unavailable: \(quarantineDirectory.path)"
            )
        }

        let quarantinedItem = quarantineDirectory.appendingPathComponent("item")
        var quarantinedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity?
        do {
            try fileManager.moveItem(at: original, to: quarantinedItem)
            quarantinedIdentity = FileSystemPathIdentity.entryIdentity(quarantinedItem)
            guard quarantinedIdentity == expectedIdentity else {
                throw ExplorerError.operationFailed(
                    "Rollback output changed before removal: \(original.path)"
                )
            }
            let currentSnapshot = try capture(at: quarantinedItem, fileManager: fileManager)
            guard currentSnapshot.matchesIgnoringRelocationMetadata(of: expectedSnapshot) else {
                throw ExplorerError.operationFailed(
                    "Rollback output contents changed before removal: \(original.path)"
                )
            }
            try fileManager.removeItem(at: quarantinedItem)
            try removeEmptyQuarantineDirectory(
                quarantineDirectory,
                expectedIdentity: quarantineDirectoryIdentity,
                fileManager: fileManager
            )
        } catch {
            var recoveryFailures: [String] = []
            if FileSystemPathIdentity.entryExists(quarantinedItem) {
                let identityToRestore = quarantinedIdentity
                    ?? FileSystemPathIdentity.entryIdentity(quarantinedItem)
                do {
                    try restoreQuarantinedItem(
                        quarantinedItem,
                        to: original,
                        expectedIdentity: identityToRestore,
                        fileManager: fileManager
                    )
                } catch let recoveryError {
                    recoveryFailures.append(
                        "quarantined item remains at \(quarantinedItem.path): \(recoveryError.localizedDescription)"
                    )
                }
            }
            do {
                try removeEmptyQuarantineDirectory(
                    quarantineDirectory,
                    expectedIdentity: quarantineDirectoryIdentity,
                    fileManager: fileManager
                )
            } catch let recoveryError {
                recoveryFailures.append(recoveryError.localizedDescription)
            }

            guard recoveryFailures.isEmpty else {
                throw ExplorerError.operationFailed(
                    "\(error.localizedDescription). Rollback quarantine recovery was incomplete: "
                        + recoveryFailures.joined(separator: "; ")
                )
            }
            throw error
        }
    }

    private static func uniqueQuarantineDirectory(nextTo url: URL) -> URL {
        let parent = url.deletingLastPathComponent()
        var candidate: URL
        repeat {
            candidate = parent.appendingPathComponent(
                ".MyMacFinder-rollback-\(UUID().uuidString)",
                isDirectory: true
            )
        } while FileSystemPathIdentity.entryExists(candidate)
        return candidate
    }

    private static func restoreQuarantinedItem(
        _ quarantinedItem: URL,
        to original: URL,
        expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity?,
        fileManager: FileManager
    ) throws {
        guard let expectedIdentity,
              FileSystemPathIdentity.entryIdentity(quarantinedItem) == expectedIdentity else {
            throw ExplorerError.operationFailed(
                "quarantined item identity changed: \(quarantinedItem.path)"
            )
        }
        guard !FileSystemPathIdentity.entryExists(original) else {
            throw ExplorerError.operationFailed(
                "original path is occupied: \(original.path)"
            )
        }
        try fileManager.moveItem(at: quarantinedItem, to: original)
        guard FileSystemPathIdentity.entryIdentity(original) == expectedIdentity else {
            throw ExplorerError.operationFailed(
                "restored item identity changed: \(original.path)"
            )
        }
    }

    private static func removeEmptyQuarantineDirectory(
        _ directory: URL,
        expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity,
        fileManager: FileManager
    ) throws {
        guard FileSystemPathIdentity.entryIdentity(directory) == expectedIdentity else {
            throw ExplorerError.operationFailed(
                "rollback quarantine identity changed: \(directory.path)"
            )
        }
        guard try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty else {
            throw ExplorerError.operationFailed(
                "rollback quarantine is not empty: \(directory.path)"
            )
        }
        try fileManager.removeItem(at: directory)
    }

    private static func relativePath(for url: URL, root: URL) -> String {
        guard url != root else {
            return ""
        }
        return String(url.path.dropFirst(root.path.count + 1))
    }

    private static func digest(of url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1_048_576)
            guard !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize())
    }

    private static func metadata(for url: URL) throws -> Metadata {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return lstat(path, &info)
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return Metadata(
            size: Int64(info.st_size),
            modificationSeconds: Int64(info.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            changeSeconds: Int64(info.st_ctimespec.tv_sec),
            changeNanoseconds: Int64(info.st_ctimespec.tv_nsec)
        )
    }
}
