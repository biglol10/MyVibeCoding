import Darwin
import Foundation

public struct FileOperationService: @unchecked Sendable {
    private let fileManager: FileManager
    private let conflictResolver: any FileConflictResolving
    private let manifestBuilder: FileOperationManifestBuilder
    private let trashItem: (URL) throws -> URL
    private let copyChunkSize: Int

    public init(
        fileManager: FileManager = .default,
        conflictResolver: any FileConflictResolving = DefaultFileConflictResolver(),
        manifestBuilder: FileOperationManifestBuilder? = nil,
        trashItem: ((URL) throws -> URL)? = nil,
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
        self.copyChunkSize = max(copyChunkSize, 1)
    }

    @discardableResult
    public func createFolder(in parent: URL) async throws -> FileOperationResult {
        let folderURL = uniqueURL(in: parent, baseName: "Untitled Folder", extension: nil)
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
        } catch {
            throw operationError(error)
        }
        return FileOperationResult(createdURLs: [folderURL])
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
        let resolution = try await resolvedDestination(
            operation: .rename,
            source: url,
            proposed: destination,
            itemIndex: 0,
            itemCount: 1
        )
        guard let resolvedDestination = resolution.url else {
            return FileOperationResult(skippedURLs: [url])
        }
        do {
            try fileManager.moveItem(at: url, to: resolvedDestination)
        } catch {
            try rollbackFailedDestination(
                resolution.replacedItem,
                partialDestination: resolvedDestination,
                originalError: error
            )
            throw operationError(error)
        }
        return FileOperationResult(
            renamedItem: FileMoveRecord(source: url, destination: resolvedDestination),
            replacedItems: resolution.replacedItem.map { [$0] } ?? []
        )
    }

    @discardableResult
    public func duplicate(_ url: URL, progress: FileOperationProgressReporter? = nil) async throws -> FileOperationResult {
        try await progress?.checkCancellation()
        await progress?.update(
            phase: .running,
            currentItemName: url.lastPathComponent,
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        let destination = copyName(for: url)
        do {
            try fileManager.copyItem(at: url, to: destination)
        } catch {
            throw operationError(error)
        }
        await progress?.update(
            phase: .running,
            currentItemName: url.lastPathComponent,
            completedUnitCount: 1,
            totalUnitCount: 1
        )
        return FileOperationResult(createdURLs: [destination])
    }

    @discardableResult
    public func copyItems(
        _ urls: [URL],
        to destinationFolder: URL,
        progress: FileOperationProgressReporter? = nil
    ) async throws -> FileOperationResult {
        try validateSourcesExist(urls)
        let byteCounts = await progressByteCounts(for: urls, progress: progress)
        let totalByteCount = totalByteCount(from: byteCounts)
        var completedByteCount: Int64 = 0

        var createdURLs: [URL] = []
        var replacedItems: [FileTrashRecord] = []
        var skippedURLs: [URL] = []

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
            let normalizedSource = source.standardizedFileURL.resolvingSymlinksInPath()
            if isDescendant(proposed.standardizedFileURL, of: normalizedSource) {
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
            try await progress?.checkCancellation()
            do {
                try await copyItem(
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
                    originalError: error
                )
                throw operationError(error)
            }
            createdURLs.append(destination)
            if let replacedItem = resolution.replacedItem {
                replacedItems.append(replacedItem)
            }
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

        return FileOperationResult(
            createdURLs: createdURLs,
            replacedItems: replacedItems,
            skippedURLs: skippedURLs
        )
    }

    @discardableResult
    public func moveItems(
        _ urls: [URL],
        to destinationFolder: URL,
        progress: FileOperationProgressReporter? = nil
    ) async throws -> FileOperationResult {
        try validateSourcesExist(urls)
        let byteCounts = await progressByteCounts(for: urls, progress: progress)
        let totalByteCount = totalByteCount(from: byteCounts)
        var completedByteCount: Int64 = 0

        let normalizedDestinationFolder = destinationFolder.standardizedFileURL.resolvingSymlinksInPath()
        var movedItems: [FileMoveRecord] = []
        var replacedItems: [FileTrashRecord] = []
        var skippedURLs: [URL] = []

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
            let normalizedSourceFolder = source
                .deletingLastPathComponent()
                .standardizedFileURL
                .resolvingSymlinksInPath()
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
            let normalizedSource = source.standardizedFileURL.resolvingSymlinksInPath()
            if isDescendant(proposed.standardizedFileURL, of: normalizedSource) {
                throw ExplorerError.operationFailed("Cannot move a folder into itself.")
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
            try await progress?.checkCancellation()
            do {
                try await moveItem(at: source, to: destination)
            } catch {
                try rollbackFailedDestination(
                    resolution.replacedItem,
                    partialDestination: destination,
                    originalError: error
                )
                throw operationError(error)
            }
            movedItems.append(FileMoveRecord(source: source, destination: destination))
            if let replacedItem = resolution.replacedItem {
                replacedItems.append(replacedItem)
            }
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

        return FileOperationResult(
            movedItems: movedItems,
            replacedItems: replacedItems,
            skippedURLs: skippedURLs
        )
    }

    @discardableResult
    public func moveToTrash(
        _ urls: [URL],
        progress: FileOperationProgressReporter? = nil
    ) async throws -> FileOperationResult {
        try validateSourcesExist(urls)
        let byteCounts = await progressByteCounts(for: urls, progress: progress)
        let totalByteCount = totalByteCount(from: byteCounts)
        var completedByteCount: Int64 = 0

        var trashedItems: [FileTrashRecord] = []
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
            do {
                trashedItems.append(try trashExistingItem(at: url))
            } catch {
                try restoreTrashedItems(trashedItems, originalError: error)
                throw operationError(error)
            }
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
        return FileOperationResult(trashedItems: trashedItems)
    }

    private struct DestinationResolution {
        var url: URL?
        var replacedItem: FileTrashRecord?
    }

    private func resolvedDestination(
        operation: FileConflictOperation,
        source: URL,
        proposed: URL,
        itemIndex: Int,
        itemCount: Int
    ) async throws -> DestinationResolution {
        if operation == .copy && source.standardizedFileURL == proposed.standardizedFileURL {
            return DestinationResolution(url: copyName(for: proposed), replacedItem: nil)
        }

        guard fileManager.fileExists(atPath: proposed.path) else {
            return DestinationResolution(url: proposed, replacedItem: nil)
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
            let replacedItem = try trashExistingItem(at: proposed)
            return DestinationResolution(url: proposed, replacedItem: replacedItem)
        case .keepBoth:
            return DestinationResolution(url: copyName(for: proposed), replacedItem: nil)
        case .skip:
            return DestinationResolution(url: nil, replacedItem: nil)
        case .cancel:
            throw FileOperationCancellation(operation: operation)
        }
    }

    private func trashExistingItem(at url: URL) throws -> FileTrashRecord {
        FileTrashRecord(original: url, trashed: try trashItem(url))
    }

    private func rollbackFailedDestination(
        _ record: FileTrashRecord?,
        partialDestination: URL,
        originalError: Error
    ) throws {
        var restorationFailures: [String] = []

        if fileManager.fileExists(atPath: partialDestination.path) {
            do {
                try fileManager.removeItem(at: partialDestination)
            } catch {
                restorationFailures.append(
                    "partial destination could not be removed: \(partialDestination.path): \(error.localizedDescription)"
                )
            }
        }
        if let record {
            if fileManager.fileExists(atPath: record.original.path) {
                restorationFailures.append("\(record.original.path) already exists")
            } else if !fileManager.fileExists(atPath: record.trashed.path) {
                restorationFailures.append("\(record.trashed.path) is missing")
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

    private func restoreTrashedItems(_ records: [FileTrashRecord], originalError: Error) throws {
        var restorationFailures: [String] = []
        for record in records.reversed() {
            guard !fileManager.fileExists(atPath: record.original.path) else {
                restorationFailures.append("\(record.original.path) already exists")
                continue
            }
            guard fileManager.fileExists(atPath: record.trashed.path) else {
                restorationFailures.append("\(record.trashed.path) is missing")
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
    ) async throws {
        if try isStreamCopyEligible(source) {
            try await copyRegularFile(at: source, to: destination, progress: progress)
            return
        }

        let fileManager = fileManager
        try await Task.detached(priority: .utility) {
            try fileManager.copyItem(at: source, to: destination)
        }.value
    }

    private func moveItem(at source: URL, to destination: URL) async throws {
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
        let fileManager = fileManager
        let chunkSize = copyChunkSize
        try await Task.detached(priority: .utility) {
            guard fileManager.createFile(atPath: destination.path, contents: nil) else {
                throw ExplorerError.operationFailed("Unable to create destination file: \(destination.path)")
            }

            let reader = try FileHandle(forReadingFrom: source)
            let writer = try FileHandle(forWritingTo: destination)
            var completedBytes: Int64 = 0

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
                try writer.close()
                try Self.copyMetadata(from: source, to: destination)
            } catch {
                try? reader.close()
                try? writer.close()
                try? fileManager.removeItem(at: destination)
                throw Self.operationError(error)
            }
        }.value
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
        while fileManager.fileExists(atPath: current.path) {
            current = candidate(index)
            index += 1
        }
        return current
    }

    private func validateSourcesExist(_ urls: [URL]) throws {
        for url in urls.map(\.standardizedFileURL) {
            guard fileManager.fileExists(atPath: url.path) else {
                throw ExplorerError.pathDoesNotExist(url.path)
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

    private func isDescendant(_ possibleChild: URL, of possibleParent: URL) -> Bool {
        let childPath = possibleChild.standardizedFileURL.path
        let parentPath = possibleParent.standardizedFileURL.path
        guard childPath != parentPath else {
            return false
        }
        return childPath.hasPrefix(parentPath + "/")
    }
}
