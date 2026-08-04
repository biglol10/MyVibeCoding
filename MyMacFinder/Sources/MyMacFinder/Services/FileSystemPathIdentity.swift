import Darwin
import Foundation

enum FileSystemPathIdentity {
    struct FileSystemEntryIdentity: Equatable, Sendable {
        var device: UInt64
        var inode: UInt64
        var generation: UInt32
        var mode: UInt32
    }

    struct EntryIdentityValues {
        var fileResourceIdentifier: Any?
        var volumeSupportsCaseSensitiveNames: Bool?
    }

    struct TrackedTrashRecord: Sendable {
        var record: FileTrashRecord
        var trashedIdentity: FileSystemEntryIdentity
    }

    static func canonicalDirectory(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    static func canonicalPathPreservingLeaf(_ url: URL) -> URL {
        canonicalDirectory(url.deletingLastPathComponent())
            .appendingPathComponent(url.lastPathComponent)
            .standardizedFileURL
    }

    static func entryExists(_ url: URL) -> Bool {
        entryIdentity(url) != nil
    }

    static func entryIdentity(_ url: URL) -> FileSystemEntryIdentity? {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return lstat(path, &info)
        }
        guard result == 0 else {
            return nil
        }
        return FileSystemEntryIdentity(
            device: UInt64(bitPattern: Int64(info.st_dev)),
            inode: UInt64(info.st_ino),
            generation: UInt32(info.st_gen),
            mode: UInt32(info.st_mode)
        )
    }

    static func isDirectory(_ identity: FileSystemEntryIdentity) -> Bool {
        identity.mode & UInt32(S_IFMT) == UInt32(S_IFDIR)
    }

    static func requireUnchangedEntry(
        at url: URL,
        expectedIdentity: FileSystemEntryIdentity,
        operation: String
    ) throws {
        guard entryIdentity(url) == expectedIdentity else {
            throw ExplorerError.operationFailed(
                "\(operation) destination changed while awaiting conflict resolution: \(url.path)"
            )
        }
    }

    static func moveToTrashSafely(
        at url: URL,
        expectedIdentity: FileSystemEntryIdentity? = nil,
        fileManager: FileManager,
        operation: String,
        trashItem: (URL) throws -> URL
    ) throws -> TrackedTrashRecord {
        guard let expectedIdentity = expectedIdentity ?? entryIdentity(url) else {
            throw ExplorerError.operationFailed("\(operation) source identity is unavailable: \(url.path)")
        }
        guard entryIdentity(url) == expectedIdentity else {
            throw ExplorerError.operationFailed(
                "\(operation) source changed before Trash move: \(url.path)"
            )
        }

        let trashedURL = try trashItem(url).standardizedFileURL
        guard let trashedIdentity = entryIdentity(trashedURL),
              trashedIdentity == expectedIdentity else {
            var rollbackFailures: [String] = []
            if let currentTrashedIdentity = entryIdentity(trashedURL) {
                if entryExists(url) {
                    rollbackFailures.append("original path already exists: \(url.path)")
                } else {
                    do {
                        try fileManager.createDirectory(
                            at: url.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try fileManager.moveItem(at: trashedURL, to: url)
                        guard entryIdentity(url) == currentTrashedIdentity else {
                            throw ExplorerError.operationFailed("restored entry identity changed: \(url.path)")
                        }
                    } catch {
                        rollbackFailures.append(
                            "could not restore changed entry from \(trashedURL.path) to \(url.path): "
                                + error.localizedDescription
                        )
                    }
                }
            } else {
                rollbackFailures.append("Trash result is missing: \(trashedURL.path)")
            }

            let rollbackDescription = rollbackFailures.isEmpty
                ? "The changed entry was restored to its original path."
                : "rollback was incomplete: " + rollbackFailures.joined(separator: "; ")
            throw ExplorerError.operationFailed(
                "\(operation) item changed during Trash move: \(url.path). \(rollbackDescription)"
            )
        }

        return TrackedTrashRecord(
            record: FileTrashRecord(original: url, trashed: trashedURL),
            trashedIdentity: trashedIdentity
        )
    }

    static func canonicalExistingEntryPreservingLeaf(_ url: URL) throws -> URL {
        let standardizedURL = url.standardizedFileURL
        let values = try standardizedURL.resourceValues(forKeys: [.nameKey])
        guard let actualName = values.name, !actualName.isEmpty else {
            throw ExplorerError.pathDoesNotExist(standardizedURL.path)
        }
        return canonicalDirectory(standardizedURL.deletingLastPathComponent())
            .appendingPathComponent(actualName)
            .standardizedFileURL
    }

    static func sameCanonicalExistingEntry(_ lhs: URL, _ rhs: URL) throws -> Bool {
        try canonicalExistingEntryPreservingLeaf(lhs) == canonicalExistingEntryPreservingLeaf(rhs)
    }

    static func isDescendant(_ possibleChild: URL, of possibleParent: URL) -> Bool {
        let childPath = possibleChild.standardizedFileURL.path
        let parentPath = possibleParent.standardizedFileURL.path
        guard childPath != parentPath else {
            return false
        }
        return childPath.hasPrefix(parentPath + "/")
    }

    static func isCaseOnlyRenameOfSameItem(source: URL, destination: URL) throws -> Bool {
        try isCaseOnlyRenameOfSameItem(
            source: source,
            destination: destination,
            resourceValuesLoader: { url in
                let values = try url.resourceValues(forKeys: [
                    .fileResourceIdentifierKey,
                    .volumeSupportsCaseSensitiveNamesKey
                ])
                return EntryIdentityValues(
                    fileResourceIdentifier: values.fileResourceIdentifier,
                    volumeSupportsCaseSensitiveNames: values.volumeSupportsCaseSensitiveNames
                )
            }
        )
    }

    static func isCaseOnlyRenameOfSameItem(
        source: URL,
        destination: URL,
        resourceValuesLoader: (URL) throws -> EntryIdentityValues
    ) throws -> Bool {
        let source = source.standardizedFileURL
        let destination = destination.standardizedFileURL
        guard source.path != destination.path,
              source.path.caseInsensitiveCompare(destination.path) == .orderedSame,
              canonicalDirectory(source.deletingLastPathComponent())
                == canonicalDirectory(destination.deletingLastPathComponent()) else {
            return false
        }

        let sourceValues = try resourceValuesLoader(source)
        guard sourceValues.volumeSupportsCaseSensitiveNames == false else {
            return false
        }
        let destinationValues = try resourceValuesLoader(destination)
        guard destinationValues.volumeSupportsCaseSensitiveNames == false,
              let sourceIdentifier = sourceValues.fileResourceIdentifier,
              let destinationIdentifier = destinationValues.fileResourceIdentifier else {
            return false
        }

        return resourceIdentifiersEqual(sourceIdentifier, destinationIdentifier)
    }

    private static func resourceIdentifiersEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if let lhs = lhs as? AnyHashable, let rhs = rhs as? AnyHashable {
            return lhs == rhs
        }
        guard let lhs = lhs as? NSObject else {
            return false
        }
        return lhs.isEqual(rhs)
    }
}
