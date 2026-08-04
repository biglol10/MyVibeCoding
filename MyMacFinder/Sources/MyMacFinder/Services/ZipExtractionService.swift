import Foundation
import ZIPFoundation

public protocol ZipExtracting: Sendable {
    func extract(
        _ zipURLs: [URL],
        to destinationFolder: URL,
        progress: FileOperationProgressReporter?
    ) async throws -> FileOperationResult
}

public extension ZipExtracting {
    func extract(_ zipURLs: [URL], to destinationFolder: URL) async throws -> FileOperationResult {
        try await extract(zipURLs, to: destinationFolder, progress: nil)
    }
}

public struct ZipExtractionService: ZipExtracting, @unchecked Sendable {
    private let fileManager: FileManager
    private let conflictResolver: any FileConflictResolving
    private let trashItem: (URL) throws -> URL

    public init(
        fileManager: FileManager = .default,
        conflictResolver: any FileConflictResolving = DefaultFileConflictResolver(),
        trashItem: ((URL) throws -> URL)? = nil
    ) {
        self.fileManager = fileManager
        self.conflictResolver = conflictResolver
        self.trashItem = trashItem ?? { url in
            var result: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &result)
            guard let result else {
                throw ExplorerError.archiveFailed("Item could not be moved to Trash: \(url.path)")
            }
            return result as URL
        }
    }

    public func extract(
        _ zipURLs: [URL],
        to destinationFolder: URL,
        progress: FileOperationProgressReporter? = nil
    ) async throws -> FileOperationResult {
        var createdURLs: [URL] = []
        var replacedItems: [FileTrashRecord] = []
        var skippedURLs: [URL] = []
        var completedExtractions: [CompletedExtraction] = []

        do {
            for (index, zipURL) in zipURLs.enumerated() {
                try await progress?.checkCancellation()
                guard zipURL.pathExtension.localizedCaseInsensitiveCompare("zip") == .orderedSame else {
                    skippedURLs.append(zipURL.standardizedFileURL)
                    continue
                }

                let baseName = zipURL.deletingPathExtension().lastPathComponent
                let proposedFolder = destinationFolder.appendingPathComponent(baseName, isDirectory: true)
                let archive: Archive
                do {
                    archive = try Archive(url: zipURL, accessMode: .read)
                } catch {
                    throw ExplorerError.archiveFailed("ZIP archive could not be read: \(zipURL.path)")
                }
                let entries = Array(archive)
                try validateEntryPaths(entries)

                let resolution = try await resolvedExtractionFolder(
                    zipURL: zipURL,
                    proposedFolder: proposedFolder,
                    index: index,
                    count: zipURLs.count
                )
                guard let extractionFolder = resolution.url else {
                    skippedURLs.append(zipURL.standardizedFileURL)
                    continue
                }

                let stagingFolder = uniqueExtractionStagingDirectory(in: destinationFolder)
                var ownedStagingEntries: [URL: FileSystemPathIdentity.FileSystemEntryIdentity] = [:]
                let completedSnapshot: FileSystemTreeSnapshot
                do {
                    try fileManager.createDirectory(
                        at: stagingFolder,
                        withIntermediateDirectories: false,
                        attributes: [.posixPermissions: 0o700]
                    )
                    guard let stagingIdentity = FileSystemPathIdentity.entryIdentity(stagingFolder) else {
                        throw ExplorerError.operationFailed(
                            "Extraction staging directory identity is unavailable: \(stagingFolder.path)"
                        )
                    }
                    ownedStagingEntries[stagingFolder.standardizedFileURL] = stagingIdentity
                    let progressEntries = entries.filter { $0.type != .directory }
                    await progress?.update(
                        phase: .running,
                        currentItemName: zipURL.lastPathComponent,
                        completedUnitCount: 0,
                        totalUnitCount: progressEntries.count
                    )

                    var completedEntryCount = 0
                    for entry in entries {
                        try await progress?.checkCancellation()
                        let destination = stagingFolder.appendingPathComponent(entry.path)
                        guard isContained(destination, in: stagingFolder) else {
                            throw ExplorerError.archiveFailed(
                                "ZIP entry attempted to extract outside destination: \(entry.path)"
                            )
                        }

                        if entry.type == .directory {
                            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                        } else {
                            try fileManager.createDirectory(
                                at: destination.deletingLastPathComponent(),
                                withIntermediateDirectories: true
                            )
                            _ = try archive.extract(entry, to: destination)
                        }
                        try recordOwnedExtractionPath(
                            destination,
                            stagingRoot: stagingFolder,
                            ownedEntries: &ownedStagingEntries
                        )

                        if entry.type != .directory {
                            completedEntryCount += 1
                            await progress?.update(
                                phase: .running,
                                currentItemName: entry.path,
                                completedUnitCount: completedEntryCount,
                                totalUnitCount: progressEntries.count
                            )
                        }
                    }
                    let stagedSnapshot = try FileSystemTreeSnapshot.capture(
                        at: stagingFolder,
                        fileManager: fileManager
                    )
                    guard let stagedRootIdentity = stagedSnapshot.rootIdentity else {
                        throw ExplorerError.operationFailed(
                            "Extraction staging directory identity is unavailable: \(stagingFolder.path)"
                        )
                    }
                    try fileManager.moveItem(at: stagingFolder, to: extractionFolder)
                    guard FileSystemPathIdentity.entryIdentity(extractionFolder) == stagedRootIdentity else {
                        throw ExplorerError.operationFailed(
                            "Extraction destination changed before commit completed: \(extractionFolder.path)"
                        )
                    }
                    completedSnapshot = try stagedSnapshot.rebasingRootMetadata(at: extractionFolder)
                } catch {
                    let operationError = archiveOperationError(error)
                    do {
                        try rollbackFailedExtraction(
                            resolution.replacedItem,
                            stagingDirectory: stagingFolder,
                            expectedStagingEntries: ownedStagingEntries
                        )
                    } catch let rollbackError {
                        throw ExplorerError.operationFailed(
                            "Extraction failed (\(operationError.localizedDescription)) and rollback was incomplete: "
                                + rollbackError.localizedDescription
                        )
                    }
                    throw operationError
                }

                let standardizedFolder = extractionFolder.standardizedFileURL
                createdURLs.append(standardizedFolder)
                completedExtractions.append(
                    CompletedExtraction(
                        url: standardizedFolder,
                        snapshot: completedSnapshot,
                        replacedItem: resolution.replacedItem
                    )
                )
                if let replacedItem = resolution.replacedItem {
                    replacedItems.append(replacedItem.record)
                }
            }
        } catch {
            let operationError = archiveOperationError(error)
            do {
                try rollbackCompletedExtractions(completedExtractions)
            } catch let rollbackError {
                throw ExplorerError.operationFailed(
                    "Extraction failed (\(operationError.localizedDescription)) and rollback was incomplete: "
                        + rollbackError.localizedDescription
                )
            }
            throw operationError
        }

        var result = FileOperationResult(
            createdURLs: createdURLs,
            replacedItems: replacedItems,
            skippedURLs: skippedURLs
        )
        for completedExtraction in completedExtractions {
            if let rootIdentity = completedExtraction.snapshot.rootIdentity {
                result.undoSourceIdentities[completedExtraction.url] = rootIdentity
            }
            if let replacedItem = completedExtraction.replacedItem {
                result.undoSourceIdentities[replacedItem.record.trashed] = replacedItem.trashedIdentity
            }
        }
        return result
    }

    private struct ExtractionResolution {
        var url: URL?
        var replacedItem: FileSystemPathIdentity.TrackedTrashRecord?
    }

    private struct CompletedExtraction {
        var url: URL
        var snapshot: FileSystemTreeSnapshot
        var replacedItem: FileSystemPathIdentity.TrackedTrashRecord?
    }

    private func resolvedExtractionFolder(
        zipURL: URL,
        proposedFolder: URL,
        index: Int,
        count: Int
    ) async throws -> ExtractionResolution {
        guard let expectedDestinationIdentity = FileSystemPathIdentity.entryIdentity(proposedFolder) else {
            return ExtractionResolution(url: proposedFolder, replacedItem: nil)
        }

        let decision = try await conflictResolver.resolve(
            FileConflict(
                operation: .extract,
                sourceURL: zipURL,
                destinationURL: proposedFolder,
                itemIndex: index,
                itemCount: count
            )
        )

        switch decision {
        case .replace:
            try FileSystemPathIdentity.requireUnchangedEntry(
                at: proposedFolder,
                expectedIdentity: expectedDestinationIdentity,
                operation: "Extraction"
            )
            let replacedItem = try trashExistingItem(
                at: proposedFolder,
                expectedIdentity: expectedDestinationIdentity
            )
            return ExtractionResolution(url: proposedFolder, replacedItem: replacedItem)
        case .keepBoth:
            return ExtractionResolution(
                url: uniqueURL(in: proposedFolder.deletingLastPathComponent(), baseName: proposedFolder.lastPathComponent),
                replacedItem: nil
            )
        case .skip:
            return ExtractionResolution(url: nil, replacedItem: nil)
        case .cancel:
            throw FileOperationCancellation(operation: .extract)
        }
    }

    private func trashExistingItem(
        at url: URL,
        expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity? = nil
    ) throws -> FileSystemPathIdentity.TrackedTrashRecord {
        try FileSystemPathIdentity.moveToTrashSafely(
            at: url,
            expectedIdentity: expectedIdentity,
            fileManager: fileManager,
            operation: "Extraction replace",
            trashItem: trashItem
        )
    }

    private func rollbackFailedExtraction(
        _ trackedRecord: FileSystemPathIdentity.TrackedTrashRecord?,
        stagingDirectory: URL,
        expectedStagingEntries: [URL: FileSystemPathIdentity.FileSystemEntryIdentity]
    ) throws {
        var failures: [String] = []
        if FileSystemPathIdentity.entryExists(stagingDirectory) {
            do {
                let currentEntries = try extractionTreeIdentities(root: stagingDirectory)
                guard currentEntries == expectedStagingEntries else {
                    throw ExplorerError.operationFailed(
                        "extraction staging contents changed before cleanup: \(stagingDirectory.path)"
                    )
                }
                try fileManager.removeItem(at: stagingDirectory)
            } catch {
                failures.append(
                    "could not safely remove partial extraction staging at \(stagingDirectory.path): "
                        + error.localizedDescription
                )
            }
        }

        if let trackedRecord {
            let record = trackedRecord.record
            if FileSystemPathIdentity.entryExists(record.original) {
                failures.append("replacement destination still exists at \(record.original.path)")
            } else if !FileSystemPathIdentity.entryExists(record.trashed) {
                failures.append("trashed replacement is missing at \(record.trashed.path)")
            } else if FileSystemPathIdentity.entryIdentity(record.trashed) != trackedRecord.trashedIdentity {
                failures.append("trashed replacement identity changed at \(record.trashed.path)")
            } else {
                do {
                    try fileManager.createDirectory(
                        at: record.original.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try fileManager.moveItem(at: record.trashed, to: record.original)
                } catch {
                    failures.append(
                        "could not restore \(record.trashed.path) to \(record.original.path): "
                            + error.localizedDescription
                    )
                }
            }

            if !FileSystemPathIdentity.entryExists(record.original) {
                failures.append("restored replacement is missing at \(record.original.path)")
            }
        }

        guard failures.isEmpty else {
            throw ExplorerError.operationFailed(failures.joined(separator: "; "))
        }
    }

    private func rollbackCompletedExtractions(_ records: [CompletedExtraction]) throws {
        var failures: [String] = []
        for record in records.reversed() {
            var didRemoveCreatedOutput = false
            do {
                try FileSystemTreeSnapshot.quarantineAndRemoveIfUnchanged(
                    at: record.url,
                    expectedSnapshot: record.snapshot,
                    fileManager: fileManager
                )
                didRemoveCreatedOutput = true
            } catch {
                failures.append("could not remove created output at \(record.url.path): \(error.localizedDescription)")
            }

            guard didRemoveCreatedOutput, let trackedReplacement = record.replacedItem else {
                continue
            }
            let replacedItem = trackedReplacement.record
            guard !FileSystemPathIdentity.entryExists(replacedItem.original) else {
                failures.append("replacement destination still exists at \(replacedItem.original.path)")
                continue
            }
            guard FileSystemPathIdentity.entryExists(replacedItem.trashed) else {
                failures.append("trashed replacement is missing at \(replacedItem.trashed.path)")
                continue
            }
            guard FileSystemPathIdentity.entryIdentity(replacedItem.trashed) == trackedReplacement.trashedIdentity else {
                failures.append("trashed replacement identity changed at \(replacedItem.trashed.path)")
                continue
            }
            do {
                try fileManager.moveItem(at: replacedItem.trashed, to: replacedItem.original)
            } catch {
                failures.append(
                    "could not restore \(replacedItem.trashed.path) to \(replacedItem.original.path): "
                        + error.localizedDescription
                )
            }
        }

        guard failures.isEmpty else {
            throw ExplorerError.operationFailed(failures.joined(separator: "; "))
        }
    }

    private func uniqueURL(in parent: URL, baseName: String) -> URL {
        var candidate = parent.appendingPathComponent("\(baseName) copy", isDirectory: true)
        var index = 2
        while FileSystemPathIdentity.entryExists(candidate) {
            candidate = parent.appendingPathComponent("\(baseName) copy \(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }

    private func uniqueExtractionStagingDirectory(in destinationFolder: URL) -> URL {
        var candidate: URL
        repeat {
            candidate = destinationFolder.appendingPathComponent(
                ".MyMacFinder-extract-\(UUID().uuidString)",
                isDirectory: true
            )
        } while FileSystemPathIdentity.entryExists(candidate)
        return candidate
    }

    private func recordOwnedExtractionPath(
        _ url: URL,
        stagingRoot: URL,
        ownedEntries: inout [URL: FileSystemPathIdentity.FileSystemEntryIdentity]
    ) throws {
        let root = stagingRoot.standardizedFileURL
        var current = url.standardizedFileURL
        while FileSystemPathIdentity.isDescendant(current, of: root) || current == root {
            guard let identity = FileSystemPathIdentity.entryIdentity(current) else {
                throw ExplorerError.operationFailed(
                    "Extraction staging entry identity is unavailable: \(current.path)"
                )
            }
            ownedEntries[current] = identity
            guard current != root else {
                break
            }
            current = current.deletingLastPathComponent().standardizedFileURL
        }
    }

    private func extractionTreeIdentities(
        root: URL
    ) throws -> [URL: FileSystemPathIdentity.FileSystemEntryIdentity] {
        let root = root.standardizedFileURL
        guard let rootIdentity = FileSystemPathIdentity.entryIdentity(root) else {
            return [:]
        }
        var identities = [root: rootIdentity]
        var directories = [root]
        var cursor = 0

        while cursor < directories.count {
            let directory = directories[cursor]
            cursor += 1
            for child in try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            ) {
                let child = child.standardizedFileURL
                guard let identity = FileSystemPathIdentity.entryIdentity(child) else {
                    throw ExplorerError.operationFailed(
                        "Extraction staging entry identity is unavailable: \(child.path)"
                    )
                }
                identities[child] = identity
                if FileSystemPathIdentity.isDirectory(identity) {
                    directories.append(child)
                }
            }
        }
        return identities
    }

    private func validateEntryPaths(_ entries: [Entry]) throws {
        let normalizedEntries = try entries.map { entry -> (entry: Entry, path: String) in
            try ArchivePathSafety.validateEntryPath(entry.path)
            let path = entry.path
                .replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/", omittingEmptySubsequences: true)
                .joined(separator: "/")
            return (entry, path)
        }
        for (itemIndex, item) in normalizedEntries.enumerated() {
            guard normalizedEntries.enumerated().contains(where: { symlinkIndex, symlink in
                symlinkIndex != itemIndex
                    && symlink.entry.type == .symlink
                    && (item.path == symlink.path || item.path.hasPrefix(symlink.path + "/"))
            }) else {
                continue
            }
            throw ExplorerError.archiveFailed(
                "ZIP entry attempted to traverse a symbolic link: \(item.entry.path)"
            )
        }
    }

    private func isContained(_ url: URL, in folder: URL) -> Bool {
        let folderPath = folder.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        return targetPath == folderPath || targetPath.hasPrefix(folderPath + "/")
    }

    private func archiveOperationError(_ error: Error) -> Error {
        if error is CancellationError || error is FileOperationCancellation {
            return error
        }
        if let error = error as? ExplorerError {
            return error
        }
        return ExplorerError.archiveFailed(error.localizedDescription)
    }
}
