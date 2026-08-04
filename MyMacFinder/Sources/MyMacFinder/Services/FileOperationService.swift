import Darwin
import Foundation

public struct FileOperationService: @unchecked Sendable {
    private let fileManager: FileManager
    private let conflictResolver: any FileConflictResolving
    private let manifestBuilder: FileOperationManifestBuilder
    private let trashItem: (URL) throws -> URL
    private let injectedMoveItemAction: ((URL, URL) throws -> Void)?
    private let copyChunkSize: Int

    public init(
        fileManager: FileManager = .default,
        conflictResolver: any FileConflictResolving = DefaultFileConflictResolver(),
        manifestBuilder: FileOperationManifestBuilder? = nil,
        trashItem: ((URL) throws -> URL)? = nil,
        moveItemAction: ((URL, URL) throws -> Void)? = nil,
        copyChunkSize: Int = 1_048_576
    ) {
        self.fileManager = fileManager
        self.conflictResolver = conflictResolver
        self.manifestBuilder = manifestBuilder ?? FileOperationManifestBuilder(fileManager: fileManager)
        self.trashItem = trashItem ?? { url in
            var result: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &result)
            guard let result else {
                throw ExplorerError.operationFailed("Item could not be moved to Trash: \(url.path)")
            }
            return result as URL
        }
        self.injectedMoveItemAction = moveItemAction
        self.copyChunkSize = max(copyChunkSize, 1)
    }

    @discardableResult
    public func createFolder(in parent: URL) async throws -> FileOperationResult {
        let folderURL = uniqueURL(in: parent, baseName: "Untitled Folder", extension: nil)
        let stagingURL = uniqueCreateFolderStagingURL(in: parent)
        var stagingIdentity: FileSystemPathIdentity.FileSystemEntryIdentity?
        do {
            try fileManager.createDirectory(
                at: stagingURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            guard let createdIdentity = FileSystemPathIdentity.entryIdentity(stagingURL) else {
                throw ExplorerError.operationFailed(
                    "Created-folder staging identity is unavailable: \(stagingURL.path)"
                )
            }
            stagingIdentity = createdIdentity
            try fileManager.moveItem(at: stagingURL, to: folderURL)
            guard FileSystemPathIdentity.entryIdentity(folderURL) == createdIdentity else {
                throw ExplorerError.operationFailed(
                    "Created folder changed before commit completed: \(folderURL.path)"
                )
            }
        } catch {
            cleanupOwnedEmptyDirectory(stagingURL, expectedIdentity: stagingIdentity)
            throw operationError(error)
        }
        var result = FileOperationResult(createdURLs: [folderURL])
        if let stagingIdentity {
            result.undoSourceIdentities[folderURL.standardizedFileURL] = stagingIdentity
        }
        return result
    }

    @discardableResult
    public func rename(_ url: URL, to newName: String) async throws -> FileOperationResult {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExplorerError.invalidPath(newName)
        }
        guard !trimmed.contains("/") && !trimmed.contains("\0") else {
            throw ExplorerError.invalidPath(trimmed)
        }
        let destination = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard destination != url else {
            return FileOperationResult()
        }
        guard let sourceIdentity = FileSystemPathIdentity.entryIdentity(url) else {
            throw ExplorerError.pathDoesNotExist(url.path)
        }
        let isCaseOnlyRename: Bool
        do {
            isCaseOnlyRename = try FileSystemPathIdentity.isCaseOnlyRenameOfSameItem(
                source: url,
                destination: destination
            )
        } catch {
            throw operationError(error)
        }
        let resolution: DestinationResolution
        if isCaseOnlyRename {
            resolution = DestinationResolution(
                url: destination,
                replacedItem: nil,
                removePartialDestinationOnFailure: false
            )
        } else {
            resolution = try await resolvedDestination(
                operation: .rename,
                source: url,
                proposed: destination,
                itemIndex: 0,
                itemCount: 1
            )
        }
        guard let resolvedDestination = resolution.url else {
            return FileOperationResult(skippedURLs: [url])
        }
        do {
            guard FileSystemPathIdentity.entryIdentity(url) == sourceIdentity else {
                throw ExplorerError.operationFailed(
                    "Rename source changed before commit: \(url.path)"
                )
            }
            try await moveItem(at: url, to: resolvedDestination)
            guard FileSystemPathIdentity.entryIdentity(resolvedDestination) == sourceIdentity else {
                throw ExplorerError.operationFailed(
                    "Rename destination changed before commit completed: \(resolvedDestination.path)"
                )
            }
        } catch {
            try rollbackFailedDestination(
                resolution.replacedItem,
                partialDestination: resolvedDestination,
                removePartialDestination: resolution.removePartialDestinationOnFailure,
                originalError: error
            )
            throw operationError(error)
        }
        var result = FileOperationResult(
            renamedItem: FileMoveRecord(source: url, destination: resolvedDestination),
            replacedItems: resolution.replacedItem.map { [$0.record] } ?? []
        )
        result.undoSourceIdentities[resolvedDestination.standardizedFileURL] = sourceIdentity
        if let replacedItem = resolution.replacedItem {
            result.undoSourceIdentities[replacedItem.record.trashed] = replacedItem.trashedIdentity
        }
        return result
    }

    @discardableResult
    public func duplicate(_ url: URL, progress: FileOperationProgressReporter? = nil) async throws -> FileOperationResult {
        guard FileSystemPathIdentity.entryExists(url) else {
            throw ExplorerError.operationFailed("Path does not exist: \(url.path)")
        }
        return try await copyItems(
            [url],
            to: url.deletingLastPathComponent(),
            progress: progress
        )
    }

    @discardableResult
    public func copyItems(
        _ urls: [URL],
        to destinationFolder: URL,
        progress: FileOperationProgressReporter? = nil
    ) async throws -> FileOperationResult {
        try validateSourcesExist(urls)
        let canonicalDestinationFolder = FileSystemPathIdentity.canonicalDirectory(destinationFolder)
        try preflightTransferRelationships(
            urls,
            canonicalDestinationFolder: canonicalDestinationFolder,
            operation: .copy
        )
        let byteCounts = await progressByteCounts(for: urls, progress: progress)
        let totalByteCount = totalByteCount(from: byteCounts)
        var completedByteCount: Int64 = 0

        var createdURLs: [URL] = []
        var createdSnapshots: [URL: FileSystemTreeSnapshot] = [:]
        var replacedItems: [FileSystemPathIdentity.TrackedTrashRecord] = []
        var completedMutations: [CompletedCopyMutation] = []
        var skippedURLs: [URL] = []

        do {
            for (index, source) in urls.enumerated() {
                try await progress?.checkCancellation()
                await progress?.update(
                    phase: .running,
                    currentItemName: source.lastPathComponent,
                    completedUnitCount: index,
                    totalUnitCount: urls.count,
                    completedBytes: completedByteCount,
                    totalBytes: totalByteCount
                )
                try await progress?.checkCancellation()
                let proposed = destinationFolder.appendingPathComponent(source.lastPathComponent)
                let canonicalSource = try FileSystemPathIdentity.canonicalExistingEntryPreservingLeaf(source)
                let canonicalProposed = canonicalDestinationFolder
                    .appendingPathComponent(source.lastPathComponent)
                if FileSystemPathIdentity.isDescendant(canonicalProposed, of: canonicalSource) {
                    throw ExplorerError.operationFailed("Cannot copy a folder into itself.")
                }

                let resolution = try await resolvedDestination(
                    operation: .copy,
                    source: source,
                    proposed: proposed,
                    itemIndex: index,
                    itemCount: urls.count
                )
                guard let destination = resolution.url else {
                    skippedURLs.append(source)
                    completedByteCount += byteCount(for: source, in: byteCounts)
                    await progress?.update(
                        phase: .running,
                        currentItemName: source.lastPathComponent,
                        completedUnitCount: index + 1,
                        totalUnitCount: urls.count,
                        completedBytes: completedByteCount,
                        totalBytes: totalByteCount
                    )
                    continue
                }
                let completedSnapshot: FileSystemTreeSnapshot
                do {
                    try await progress?.checkCancellation()
                    completedSnapshot = try await copyItem(
                        at: source,
                        to: destination,
                        progress: ByteProgressContext(
                            progress: progress,
                            currentItemName: source.lastPathComponent,
                            completedUnitCount: index,
                            totalUnitCount: urls.count,
                            baseCompletedBytes: completedByteCount,
                            totalBytes: totalByteCount
                        )
                    )
                } catch {
                    try rollbackFailedDestination(
                        resolution.replacedItem,
                        partialDestination: destination,
                        removePartialDestination: resolution.removePartialDestinationOnFailure,
                        originalError: error
                    )
                    throw operationError(error)
                }
                if let replacedItem = resolution.replacedItem {
                    replacedItems.append(replacedItem)
                    completedMutations.append(.replaced(replacedItem))
                }
                createdURLs.append(destination)
                createdSnapshots[destination.standardizedFileURL] = completedSnapshot
                completedMutations.append(.created(url: destination, snapshot: completedSnapshot))
                completedByteCount += byteCount(for: source, in: byteCounts)
                await progress?.update(
                    phase: .running,
                    currentItemName: source.lastPathComponent,
                    completedUnitCount: index + 1,
                    totalUnitCount: urls.count,
                    completedBytes: completedByteCount,
                    totalBytes: totalByteCount
                )
            }
        } catch {
            try rollbackCompletedCopies(completedMutations, originalError: error)
            throw operationError(error)
        }

        var result = FileOperationResult(
            createdURLs: createdURLs,
            replacedItems: replacedItems.map(\.record),
            skippedURLs: skippedURLs
        )
        for (url, snapshot) in createdSnapshots {
            if let rootIdentity = snapshot.rootIdentity {
                result.undoSourceIdentities[url] = rootIdentity
            }
        }
        for replacedItem in replacedItems {
            result.undoSourceIdentities[replacedItem.record.trashed] = replacedItem.trashedIdentity
        }
        return result
    }

    @discardableResult
    public func moveItems(
        _ urls: [URL],
        to destinationFolder: URL,
        progress: FileOperationProgressReporter? = nil
    ) async throws -> FileOperationResult {
        try validateSourcesExist(urls)
        let normalizedDestinationFolder = FileSystemPathIdentity.canonicalDirectory(destinationFolder)
        try preflightTransferRelationships(
            urls,
            canonicalDestinationFolder: normalizedDestinationFolder,
            operation: .move
        )
        let byteCounts = await progressByteCounts(for: urls, progress: progress)
        let totalByteCount = totalByteCount(from: byteCounts)
        var completedByteCount: Int64 = 0

        var movedItems: [TrackedMoveRecord] = []
        var replacedItems: [FileSystemPathIdentity.TrackedTrashRecord] = []
        var completedMutations: [CompletedMoveMutation] = []
        var skippedURLs: [URL] = []

        do {
            for (index, source) in urls.enumerated() {
                try await progress?.checkCancellation()
                await progress?.update(
                    phase: .running,
                    currentItemName: source.lastPathComponent,
                    completedUnitCount: index,
                    totalUnitCount: urls.count,
                    completedBytes: completedByteCount,
                    totalBytes: totalByteCount
                )
                try await progress?.checkCancellation()
                let normalizedSourceFolder = FileSystemPathIdentity.canonicalDirectory(
                    source.deletingLastPathComponent()
                )
                if normalizedSourceFolder == normalizedDestinationFolder {
                    skippedURLs.append(source)
                    completedByteCount += byteCount(for: source, in: byteCounts)
                    await progress?.update(
                        phase: .running,
                        currentItemName: source.lastPathComponent,
                        completedUnitCount: index + 1,
                        totalUnitCount: urls.count,
                        completedBytes: completedByteCount,
                        totalBytes: totalByteCount
                    )
                    continue
                }

                let proposed = destinationFolder.appendingPathComponent(source.lastPathComponent)
                let canonicalSource = try FileSystemPathIdentity.canonicalExistingEntryPreservingLeaf(source)
                let canonicalProposed = normalizedDestinationFolder.appendingPathComponent(source.lastPathComponent)
                if FileSystemPathIdentity.isDescendant(canonicalProposed, of: canonicalSource) {
                    throw ExplorerError.operationFailed("Cannot move a folder into itself.")
                }
                guard let sourceIdentity = FileSystemPathIdentity.entryIdentity(source) else {
                    throw ExplorerError.pathDoesNotExist(source.path)
                }

                let resolution = try await resolvedDestination(
                    operation: .move,
                    source: source,
                    proposed: proposed,
                    itemIndex: index,
                    itemCount: urls.count
                )
                guard let destination = resolution.url else {
                    skippedURLs.append(source)
                    completedByteCount += byteCount(for: source, in: byteCounts)
                    await progress?.update(
                        phase: .running,
                        currentItemName: source.lastPathComponent,
                        completedUnitCount: index + 1,
                        totalUnitCount: urls.count,
                        completedBytes: completedByteCount,
                        totalBytes: totalByteCount
                    )
                    continue
                }
                do {
                    try await progress?.checkCancellation()
                    guard FileSystemPathIdentity.entryIdentity(source) == sourceIdentity else {
                        throw ExplorerError.operationFailed(
                            "Move source changed before commit: \(source.path)"
                        )
                    }
                    try await moveItem(at: source, to: destination)
                    guard FileSystemPathIdentity.entryIdentity(destination) == sourceIdentity else {
                        throw ExplorerError.operationFailed(
                            "Move destination changed before commit completed: \(destination.path)"
                        )
                    }
                } catch {
                    try rollbackFailedDestination(
                        resolution.replacedItem,
                        partialDestination: destination,
                        removePartialDestination: resolution.removePartialDestinationOnFailure,
                        originalError: error
                    )
                    throw operationError(error)
                }
                let trackedMove = TrackedMoveRecord(
                    record: FileMoveRecord(source: source, destination: destination),
                    destinationIdentity: sourceIdentity
                )
                movedItems.append(trackedMove)
                if let replacedItem = resolution.replacedItem {
                    replacedItems.append(replacedItem)
                    completedMutations.append(.replaced(replacedItem))
                }
                completedMutations.append(.moved(trackedMove))
                completedByteCount += byteCount(for: source, in: byteCounts)
                await progress?.update(
                    phase: .running,
                    currentItemName: source.lastPathComponent,
                    completedUnitCount: index + 1,
                    totalUnitCount: urls.count,
                    completedBytes: completedByteCount,
                    totalBytes: totalByteCount
                )
            }
        } catch {
            try await rollbackCompletedMoves(
                completedMutations,
                originalError: error
            )
            throw operationError(error)
        }

        var result = FileOperationResult(
            movedItems: movedItems.map(\.record),
            replacedItems: replacedItems.map(\.record),
            skippedURLs: skippedURLs
        )
        for movedItem in movedItems {
            result.undoSourceIdentities[movedItem.record.destination] = movedItem.destinationIdentity
        }
        for replacedItem in replacedItems {
            result.undoSourceIdentities[replacedItem.record.trashed] = replacedItem.trashedIdentity
        }
        return result
    }

    @discardableResult
    public func moveToTrash(
        _ urls: [URL],
        progress: FileOperationProgressReporter? = nil
    ) async throws -> FileOperationResult {
        try await moveToTrash(
            urls,
            expectedIdentities: nil,
            progress: progress
        )
    }

    func moveToTrash(
        _ urls: [URL],
        expectedIdentities: [URL: FileSystemPathIdentity.FileSystemEntryIdentity],
        progress: FileOperationProgressReporter? = nil
    ) async throws -> FileOperationResult {
        try await moveToTrash(
            urls,
            expectedIdentities: Optional(expectedIdentities),
            progress: progress
        )
    }

    private func moveToTrash(
        _ urls: [URL],
        expectedIdentities: [URL: FileSystemPathIdentity.FileSystemEntryIdentity]?,
        progress: FileOperationProgressReporter?
    ) async throws -> FileOperationResult {
        try validateSourcesExist(urls)
        let byteCounts = await progressByteCounts(for: urls, progress: progress)
        let totalByteCount = totalByteCount(from: byteCounts)
        var completedByteCount: Int64 = 0

        var trashedItems: [FileSystemPathIdentity.TrackedTrashRecord] = []
        do {
            for (index, url) in urls.enumerated() {
                try await progress?.checkCancellation()
                await progress?.update(
                    phase: .running,
                    currentItemName: url.lastPathComponent,
                    completedUnitCount: index,
                    totalUnitCount: urls.count,
                    completedBytes: completedByteCount,
                    totalBytes: totalByteCount
                )
                try await progress?.checkCancellation()
                let expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity?
                if let expectedIdentities {
                    guard let ownedIdentity = expectedIdentities[url.standardizedFileURL] else {
                        throw ExplorerError.operationFailed(
                            "Trash source ownership is unavailable: \(url.path)"
                        )
                    }
                    expectedIdentity = ownedIdentity
                } else {
                    expectedIdentity = nil
                }
                trashedItems.append(
                    try trashExistingItem(
                        at: url,
                        expectedIdentity: expectedIdentity,
                        operation: "Trash"
                    )
                )
                completedByteCount += byteCount(for: url, in: byteCounts)
                await progress?.update(
                    phase: .running,
                    currentItemName: url.lastPathComponent,
                    completedUnitCount: index + 1,
                    totalUnitCount: urls.count,
                    completedBytes: completedByteCount,
                    totalBytes: totalByteCount
                )
            }
        } catch {
            try restoreTrashedItems(trashedItems, originalError: error)
            throw operationError(error)
        }
        var result = FileOperationResult(trashedItems: trashedItems.map(\.record))
        for trashedItem in trashedItems {
            result.undoSourceIdentities[trashedItem.record.trashed] = trashedItem.trashedIdentity
        }
        return result
    }

    private struct TrackedMoveRecord {
        var record: FileMoveRecord
        var destinationIdentity: FileSystemPathIdentity.FileSystemEntryIdentity
    }

    private enum CompletedCopyMutation {
        case replaced(FileSystemPathIdentity.TrackedTrashRecord)
        case created(url: URL, snapshot: FileSystemTreeSnapshot)
    }

    private enum CompletedMoveMutation {
        case replaced(FileSystemPathIdentity.TrackedTrashRecord)
        case moved(TrackedMoveRecord)
    }

    private struct DestinationResolution {
        var url: URL?
        var replacedItem: FileSystemPathIdentity.TrackedTrashRecord?
        var removePartialDestinationOnFailure: Bool = false
    }

    private func resolvedDestination(
        operation: FileConflictOperation,
        source: URL,
        proposed: URL,
        itemIndex: Int,
        itemCount: Int
    ) async throws -> DestinationResolution {
        guard let expectedDestinationIdentity = FileSystemPathIdentity.entryIdentity(proposed) else {
            return DestinationResolution(url: proposed, replacedItem: nil)
        }

        if operation == .copy,
           try FileSystemPathIdentity.sameCanonicalExistingEntry(source, proposed) {
            return DestinationResolution(url: copyName(for: proposed), replacedItem: nil)
        }

        let conflict = FileConflict(
            operation: operation,
            sourceURL: source,
            destinationURL: proposed,
            itemIndex: itemIndex,
            itemCount: itemCount
        )

        let decision = try await conflictResolver.resolve(conflict)
        switch decision {
        case .replace:
            try FileSystemPathIdentity.requireUnchangedEntry(
                at: proposed,
                expectedIdentity: expectedDestinationIdentity,
                operation: operation.rawValue.capitalized
            )
            let replacedItem = try trashExistingItem(
                at: proposed,
                expectedIdentity: expectedDestinationIdentity,
                operation: operation.title
            )
            return DestinationResolution(url: proposed, replacedItem: replacedItem)
        case .keepBoth:
            return DestinationResolution(url: copyName(for: proposed), replacedItem: nil)
        case .skip:
            return DestinationResolution(url: nil, replacedItem: nil)
        case .cancel:
            throw FileOperationCancellation(operation: operation)
        }
    }

    private func trashExistingItem(
        at url: URL,
        expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity? = nil,
        operation: String = "Trash"
    ) throws -> FileSystemPathIdentity.TrackedTrashRecord {
        try FileSystemPathIdentity.moveToTrashSafely(
            at: url,
            expectedIdentity: expectedIdentity,
            fileManager: fileManager,
            operation: operation,
            trashItem: trashItem
        )
    }

    private func rollbackFailedDestination(
        _ trackedRecord: FileSystemPathIdentity.TrackedTrashRecord?,
        partialDestination: URL,
        removePartialDestination: Bool,
        originalError: Error
    ) throws {
        var restorationFailures: [String] = []

        if removePartialDestination, FileSystemPathIdentity.entryExists(partialDestination) {
            do {
                try fileManager.removeItem(at: partialDestination)
            } catch {
                restorationFailures.append(
                    "partial destination could not be removed: \(partialDestination.path): \(error.localizedDescription)"
                )
            }
        }
        if let trackedRecord {
            let record = trackedRecord.record
            if FileSystemPathIdentity.entryExists(record.original) {
                restorationFailures.append("\(record.original.path) already exists")
            } else if !FileSystemPathIdentity.entryExists(record.trashed) {
                restorationFailures.append("\(record.trashed.path) is missing")
            } else if FileSystemPathIdentity.entryIdentity(record.trashed) != trackedRecord.trashedIdentity {
                restorationFailures.append("\(record.trashed.path) identity changed")
            } else {
                do {
                    try fileManager.createDirectory(
                        at: record.original.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try fileManager.moveItem(at: record.trashed, to: record.original)
                } catch {
                    restorationFailures.append("\(record.original.path): \(error.localizedDescription)")
                }
            }
        }

        guard restorationFailures.isEmpty else {
            throw ExplorerError.operationFailed(
                "Operation failed (\(originalError.localizedDescription)) and rollback was incomplete: "
                    + restorationFailures.joined(separator: "; ")
            )
        }
    }

    private func restoreTrashedItems(
        _ records: [FileSystemPathIdentity.TrackedTrashRecord],
        originalError: Error
    ) throws {
        var restorationFailures: [String] = []
        for trackedRecord in records.reversed() {
            let record = trackedRecord.record
            guard !FileSystemPathIdentity.entryExists(record.original) else {
                restorationFailures.append("\(record.original.path) already exists")
                continue
            }
            guard FileSystemPathIdentity.entryExists(record.trashed) else {
                restorationFailures.append("\(record.trashed.path) is missing")
                continue
            }
            guard FileSystemPathIdentity.entryIdentity(record.trashed) == trackedRecord.trashedIdentity else {
                restorationFailures.append("\(record.trashed.path) identity changed")
                continue
            }
            do {
                try fileManager.createDirectory(
                    at: record.original.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: record.trashed, to: record.original)
            } catch {
                restorationFailures.append("\(record.original.path): \(error.localizedDescription)")
            }
        }

        guard restorationFailures.isEmpty else {
            throw ExplorerError.operationFailed(
                "Trash failed (\(originalError.localizedDescription)) and rollback was incomplete: "
                    + restorationFailures.joined(separator: "; ")
            )
        }
    }

    private func rollbackCompletedCopies(
        _ mutations: [CompletedCopyMutation],
        originalError: Error
    ) throws {
        var failures: [String] = []
        for mutation in mutations.reversed() {
            switch mutation {
            case .created(let url, let expectedSnapshot):
                do {
                    try FileSystemTreeSnapshot.quarantineAndRemoveIfUnchanged(
                        at: url,
                        expectedSnapshot: expectedSnapshot,
                        fileManager: fileManager
                    )
                } catch {
                    failures.append("could not safely remove created copy at \(url.path): \(error.localizedDescription)")
                }
            case .replaced(let trackedRecord):
                let record = trackedRecord.record
                guard !FileSystemPathIdentity.entryExists(record.original) else {
                    failures.append("replacement destination still exists at \(record.original.path)")
                    continue
                }
                guard FileSystemPathIdentity.entryIdentity(record.trashed) == trackedRecord.trashedIdentity else {
                    failures.append("trashed replacement identity changed at \(record.trashed.path)")
                    continue
                }
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
        }

        guard failures.isEmpty else {
            throw ExplorerError.operationFailed(
                "Copy failed (\(originalError.localizedDescription)) and rollback was incomplete: "
                    + failures.joined(separator: "; ")
            )
        }
    }

    private func rollbackCompletedMoves(
        _ mutations: [CompletedMoveMutation],
        originalError: Error
    ) async throws {
        var failures: [String] = []
        for mutation in mutations.reversed() {
            switch mutation {
            case .moved(let trackedRecord):
                let record = trackedRecord.record
                guard !FileSystemPathIdentity.entryExists(record.source) else {
                    failures.append("\(record.source.path) already exists")
                    continue
                }
                guard FileSystemPathIdentity.entryExists(record.destination) else {
                    failures.append("\(record.destination.path) is missing")
                    continue
                }
                guard FileSystemPathIdentity.entryIdentity(record.destination) == trackedRecord.destinationIdentity else {
                    failures.append("\(record.destination.path) identity changed")
                    continue
                }
                do {
                    try await moveItem(at: record.destination, to: record.source)
                } catch {
                    failures.append(
                        "\(record.destination.path) -> \(record.source.path): \(error.localizedDescription)"
                    )
                }
            case .replaced(let trackedRecord):
                let record = trackedRecord.record
                guard !FileSystemPathIdentity.entryExists(record.original) else {
                    failures.append("\(record.original.path) already exists")
                    continue
                }
                guard FileSystemPathIdentity.entryExists(record.trashed) else {
                    failures.append("\(record.trashed.path) is missing")
                    continue
                }
                guard FileSystemPathIdentity.entryIdentity(record.trashed) == trackedRecord.trashedIdentity else {
                    failures.append("\(record.trashed.path) identity changed")
                    continue
                }
                do {
                    try await moveItem(at: record.trashed, to: record.original)
                } catch {
                    failures.append(
                        "\(record.trashed.path) -> \(record.original.path): \(error.localizedDescription)"
                    )
                }
            }
        }

        guard failures.isEmpty else {
            throw ExplorerError.operationFailed(
                "Move failed (\(originalError.localizedDescription)) and rollback was incomplete: "
                    + failures.joined(separator: "; ")
            )
        }
    }

    private struct ByteProgressContext: Sendable {
        var progress: FileOperationProgressReporter?
        var currentItemName: String
        var completedUnitCount: Int
        var totalUnitCount: Int
        var baseCompletedBytes: Int64
        var totalBytes: Int64?

        func update(copiedBytes: Int64) async {
            await progress?.update(
                phase: .running,
                currentItemName: currentItemName,
                completedUnitCount: completedUnitCount,
                totalUnitCount: totalUnitCount,
                completedBytes: baseCompletedBytes + copiedBytes,
                totalBytes: totalBytes
            )
        }

        func checkCancellation() async throws {
            try await progress?.checkCancellation()
        }
    }

    private func copyItem(
        at source: URL,
        to destination: URL,
        progress: ByteProgressContext
    ) async throws -> FileSystemTreeSnapshot {
        let stagingDirectory = uniqueCopyStagingDirectory(nextTo: destination)
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        guard let stagingDirectoryIdentity = FileSystemPathIdentity.entryIdentity(stagingDirectory) else {
            throw ExplorerError.operationFailed(
                "Copy staging directory identity is unavailable: \(stagingDirectory.path)"
            )
        }
        let stagingURL = stagingDirectory.appendingPathComponent(destination.lastPathComponent)
        var stagingEntryIdentity: FileSystemPathIdentity.FileSystemEntryIdentity?
        do {
            if try isStreamCopyEligible(source) {
                guard fileManager.createFile(atPath: stagingURL.path, contents: nil),
                      let createdIdentity = FileSystemPathIdentity.entryIdentity(stagingURL) else {
                    throw ExplorerError.operationFailed("Unable to create copy staging file: \(stagingURL.path)")
                }
                stagingEntryIdentity = createdIdentity
                try await copyRegularFile(at: source, to: stagingURL, progress: progress)
            } else {
                let fileManager = fileManager
                try await Task.detached(priority: .utility) {
                    try fileManager.copyItem(at: source, to: stagingURL)
                }.value
                guard let createdIdentity = FileSystemPathIdentity.entryIdentity(stagingURL) else {
                    throw ExplorerError.operationFailed("Copy staging entry is missing: \(stagingURL.path)")
                }
                stagingEntryIdentity = createdIdentity
            }
            let stagedSnapshot = try FileSystemTreeSnapshot.capture(
                at: stagingURL,
                fileManager: fileManager
            )
            guard let stagedRootIdentity = stagedSnapshot.rootIdentity else {
                throw ExplorerError.operationFailed(
                    "Copy staging entry identity is unavailable: \(stagingURL.path)"
                )
            }
            try await moveItem(at: stagingURL, to: destination)
            guard FileSystemPathIdentity.entryIdentity(destination) == stagedRootIdentity else {
                throw ExplorerError.operationFailed(
                    "Copy destination changed before commit completed: \(destination.path)"
                )
            }
            let completedSnapshot = try stagedSnapshot.rebasingRootMetadata(at: destination)
            removeCommittedCopyStagingDirectory(
                stagingDirectory,
                expectedIdentity: stagingDirectoryIdentity
            )
            return completedSnapshot
        } catch {
            do {
                try cleanupOwnedCopyStagingDirectory(
                    stagingDirectory,
                    expectedDirectoryIdentity: stagingDirectoryIdentity,
                    stagingEntry: stagingURL,
                    expectedEntryIdentity: stagingEntryIdentity
                )
            } catch let cleanupError {
                throw ExplorerError.operationFailed(
                    "Copy failed (\(error.localizedDescription)) and staging cleanup was incomplete at "
                        + "\(stagingDirectory.path): \(cleanupError.localizedDescription)"
                )
            }
            throw error
        }
    }

    private func uniqueCopyStagingDirectory(nextTo destination: URL) -> URL {
        let parent = destination.deletingLastPathComponent()
        var candidate: URL
        repeat {
            candidate = parent.appendingPathComponent(
                ".MyMacFinder-copy-\(UUID().uuidString)",
                isDirectory: true
            )
        } while FileSystemPathIdentity.entryExists(candidate)
        return candidate
    }

    private func uniqueCreateFolderStagingURL(in parent: URL) -> URL {
        var candidate: URL
        repeat {
            candidate = parent.appendingPathComponent(
                ".MyMacFinder-new-folder-\(UUID().uuidString)",
                isDirectory: true
            )
        } while FileSystemPathIdentity.entryExists(candidate)
        return candidate
    }

    private func cleanupOwnedEmptyDirectory(
        _ directory: URL,
        expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity?
    ) {
        guard let expectedIdentity,
              FileSystemPathIdentity.entryIdentity(directory) == expectedIdentity else {
            return
        }
        do {
            guard try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty else {
                return
            }
            try fileManager.removeItem(at: directory)
        } catch {
            NSLog(
                "MyMacFinder could not remove empty created-folder staging directory %@: %@",
                directory.path,
                error.localizedDescription
            )
        }
    }

    private func cleanupOwnedCopyStagingDirectory(
        _ directory: URL,
        expectedDirectoryIdentity: FileSystemPathIdentity.FileSystemEntryIdentity,
        stagingEntry: URL,
        expectedEntryIdentity: FileSystemPathIdentity.FileSystemEntryIdentity?
    ) throws {
        guard let currentDirectoryIdentity = FileSystemPathIdentity.entryIdentity(directory) else {
            return
        }
        guard currentDirectoryIdentity == expectedDirectoryIdentity else {
            throw ExplorerError.operationFailed("Copy staging directory identity changed: \(directory.path)")
        }

        let childNames = try fileManager.contentsOfDirectory(atPath: directory.path)
        if let expectedEntryIdentity {
            guard childNames.allSatisfy({ $0 == stagingEntry.lastPathComponent }) else {
                throw ExplorerError.operationFailed("Copy staging directory contains an unrelated entry: \(directory.path)")
            }
            if let currentEntryIdentity = FileSystemPathIdentity.entryIdentity(stagingEntry),
               currentEntryIdentity != expectedEntryIdentity {
                throw ExplorerError.operationFailed("Copy staging entry identity changed: \(stagingEntry.path)")
            }
        } else if !childNames.isEmpty {
            throw ExplorerError.operationFailed(
                "Copy staging entry ownership could not be verified before cleanup: \(directory.path)"
            )
        }
        try fileManager.removeItem(at: directory)
    }

    private func removeCommittedCopyStagingDirectory(
        _ directory: URL,
        expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity
    ) {
        guard FileSystemPathIdentity.entryIdentity(directory) == expectedIdentity else {
            NSLog("MyMacFinder left a changed copy staging directory untouched: %@", directory.path)
            return
        }
        do {
            guard try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty else {
                NSLog("MyMacFinder left a non-empty copy staging directory untouched: %@", directory.path)
                return
            }
            try fileManager.removeItem(at: directory)
        } catch {
            NSLog("MyMacFinder could not remove empty copy staging directory %@: %@", directory.path, error.localizedDescription)
        }
    }

    private func moveItem(at source: URL, to destination: URL) async throws {
        if let injectedMoveItemAction {
            try injectedMoveItemAction(source, destination)
            return
        }
        let fileManager = fileManager
        try await Task.detached(priority: .utility) {
            try fileManager.moveItem(at: source, to: destination)
        }.value
    }

    private func isStreamCopyEligible(_ source: URL) throws -> Bool {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func copyRegularFile(
        at source: URL,
        to destination: URL,
        progress: ByteProgressContext
    ) async throws {
        let chunkSize = copyChunkSize
        try await Task.detached(priority: .utility) {
            let reader = try FileHandle(forReadingFrom: source)
            let writer: FileHandle
            do {
                writer = try FileHandle(forWritingTo: destination)
            } catch {
                var closeFailures: [String] = []
                Self.closeFileHandle(reader, label: "source", failures: &closeFailures)
                guard closeFailures.isEmpty else {
                    throw ExplorerError.operationFailed(
                        "Copy failed (\(error.localizedDescription)) and file handle cleanup was incomplete: "
                            + closeFailures.joined(separator: "; ")
                    )
                }
                throw Self.operationError(error)
            }
            var completedBytes: Int64 = 0
            var readerIsOpen = true
            var writerIsOpen = true

            do {
                while true {
                    try await progress.checkCancellation()
                    let chunk = try reader.read(upToCount: chunkSize) ?? Data()
                    guard !chunk.isEmpty else {
                        break
                    }
                    try writer.write(contentsOf: chunk)
                    completedBytes += Int64(chunk.count)
                    await progress.update(copiedBytes: completedBytes)
                }

                try reader.close()
                readerIsOpen = false
                try writer.close()
                writerIsOpen = false
                try Self.copyMetadata(from: source, to: destination)
            } catch {
                var closeFailures: [String] = []
                if readerIsOpen {
                    Self.closeFileHandle(reader, label: "source", failures: &closeFailures)
                }
                if writerIsOpen {
                    Self.closeFileHandle(writer, label: "staging destination", failures: &closeFailures)
                }
                guard closeFailures.isEmpty else {
                    throw ExplorerError.operationFailed(
                        "Copy failed (\(error.localizedDescription)) and file handle cleanup was incomplete: "
                            + closeFailures.joined(separator: "; ")
                    )
                }
                throw Self.operationError(error)
            }
        }.value
    }

    private static func closeFileHandle(
        _ handle: FileHandle,
        label: String,
        failures: inout [String]
    ) {
        do {
            try handle.close()
        } catch {
            failures.append("\(label): \(error.localizedDescription)")
        }
    }

    private static func copyMetadata(from source: URL, to destination: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                copyfile(
                    sourcePath,
                    destinationPath,
                    nil,
                    copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW)
                )
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func operationError(_ error: Error) -> Error {
        Self.operationError(error)
    }

    private static func operationError(_ error: Error) -> Error {
        if error is CancellationError || error is FileOperationCancellation {
            return error
        }
        if let error = error as? ExplorerError {
            return error
        }
        return ExplorerError.operationFailed(error.localizedDescription)
    }

    private func copyName(for url: URL) -> URL {
        let parent = url.deletingLastPathComponent()
        let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
        let stem = ext == nil ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        return uniqueURL(in: parent, baseName: "\(stem) copy", extension: ext)
    }

    private func uniqueURL(in parent: URL, baseName: String, extension ext: String?) -> URL {
        func candidate(_ suffix: Int?) -> URL {
            let name = suffix.map { "\(baseName) \($0)" } ?? baseName
            if let ext {
                return parent.appendingPathComponent(name).appendingPathExtension(ext)
            }
            return parent.appendingPathComponent(name)
        }

        var current = candidate(nil)
        var index = 2
        while FileSystemPathIdentity.entryExists(current) {
            current = candidate(index)
            index += 1
        }
        return current
    }

    private func validateSourcesExist(_ urls: [URL]) throws {
        for url in urls.map(\.standardizedFileURL) {
            guard FileSystemPathIdentity.entryExists(url) else {
                throw ExplorerError.pathDoesNotExist(url.path)
            }
        }
    }

    private func preflightTransferRelationships(
        _ urls: [URL],
        canonicalDestinationFolder: URL,
        operation: FileConflictOperation
    ) throws {
        for source in urls {
            let canonicalSource = try FileSystemPathIdentity.canonicalExistingEntryPreservingLeaf(source)
            let canonicalProposed = canonicalDestinationFolder.appendingPathComponent(source.lastPathComponent)
            guard !FileSystemPathIdentity.isDescendant(canonicalProposed, of: canonicalSource) else {
                let verb = operation == .copy ? "copy" : "move"
                throw ExplorerError.operationFailed("Cannot \(verb) a folder into itself.")
            }
        }
    }

    private func progressByteCounts(
        for urls: [URL],
        progress: FileOperationProgressReporter?
    ) async -> [URL: Int64]? {
        guard progress != nil else {
            return nil
        }
        let builder = manifestBuilder
        return await Task.detached {
            var byteCounts: [URL: Int64] = [:]
            for url in urls {
                guard let manifest = try? builder.manifest(for: [url]) else {
                    return nil
                }
                byteCounts[url.standardizedFileURL] = manifest.totalByteCount
            }
            return byteCounts
        }.value
    }

    private func totalByteCount(from byteCounts: [URL: Int64]?) -> Int64? {
        guard let byteCounts else {
            return nil
        }
        return byteCounts.values.reduce(0, +)
    }

    private func byteCount(for url: URL, in byteCounts: [URL: Int64]?) -> Int64 {
        byteCounts?[url.standardizedFileURL] ?? 0
    }

}
