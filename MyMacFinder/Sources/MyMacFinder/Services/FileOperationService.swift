import Foundation

public struct FileOperationService: @unchecked Sendable {
    private let fileManager: FileManager
    private let conflictResolver: any FileConflictResolving

    public init(
        fileManager: FileManager = .default,
        conflictResolver: any FileConflictResolving = DefaultFileConflictResolver()
    ) {
        self.fileManager = fileManager
        self.conflictResolver = conflictResolver
    }

    @discardableResult
    public func createFolder(in parent: URL) async throws -> FileOperationResult {
        let folderURL = uniqueURL(in: parent, baseName: "Untitled Folder", extension: nil)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
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
        try fileManager.moveItem(at: url, to: resolvedDestination)
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
        try fileManager.copyItem(at: url, to: destination)
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
        var createdURLs: [URL] = []
        var replacedItems: [FileTrashRecord] = []
        var skippedURLs: [URL] = []

        for (index, source) in urls.enumerated() {
            try await progress?.checkCancellation()
            await progress?.update(
                phase: .running,
                currentItemName: source.lastPathComponent,
                completedUnitCount: index,
                totalUnitCount: urls.count
            )
            let proposed = destinationFolder.appendingPathComponent(source.lastPathComponent)
            let normalizedSource = source.standardizedFileURL.resolvingSymlinksInPath()
            if isDescendant(proposed.standardizedFileURL, of: normalizedSource) {
                throw ExplorerError.readFailed("Cannot copy a folder into itself.")
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
                continue
            }
            try fileManager.copyItem(at: source, to: destination)
            createdURLs.append(destination)
            if let replacedItem = resolution.replacedItem {
                replacedItems.append(replacedItem)
            }
            await progress?.update(
                phase: .running,
                currentItemName: source.lastPathComponent,
                completedUnitCount: index + 1,
                totalUnitCount: urls.count
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
                totalUnitCount: urls.count
            )
            let normalizedSourceFolder = source
                .deletingLastPathComponent()
                .standardizedFileURL
                .resolvingSymlinksInPath()
            if normalizedSourceFolder == normalizedDestinationFolder {
                skippedURLs.append(source)
                continue
            }

            let proposed = destinationFolder.appendingPathComponent(source.lastPathComponent)
            let normalizedSource = source.standardizedFileURL.resolvingSymlinksInPath()
            if isDescendant(proposed.standardizedFileURL, of: normalizedSource) {
                throw ExplorerError.readFailed("Cannot move a folder into itself.")
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
                continue
            }
            try fileManager.moveItem(at: source, to: destination)
            movedItems.append(FileMoveRecord(source: source, destination: destination))
            if let replacedItem = resolution.replacedItem {
                replacedItems.append(replacedItem)
            }
            await progress?.update(
                phase: .running,
                currentItemName: source.lastPathComponent,
                completedUnitCount: index + 1,
                totalUnitCount: urls.count
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
        var trashedItems: [FileTrashRecord] = []
        for (index, url) in urls.enumerated() {
            try await progress?.checkCancellation()
            await progress?.update(
                phase: .running,
                currentItemName: url.lastPathComponent,
                completedUnitCount: index,
                totalUnitCount: urls.count
            )
            trashedItems.append(try trashExistingItem(at: url))
            await progress?.update(
                phase: .running,
                currentItemName: url.lastPathComponent,
                completedUnitCount: index + 1,
                totalUnitCount: urls.count
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
        var result: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &result)
        guard let result else {
            throw ExplorerError.readFailed("Item could not be moved to Trash: \(url.path)")
        }
        return FileTrashRecord(original: url, trashed: result as URL)
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

    private func isDescendant(_ possibleChild: URL, of possibleParent: URL) -> Bool {
        let childPath = possibleChild.standardizedFileURL.path
        let parentPath = possibleParent.standardizedFileURL.path
        guard childPath != parentPath else {
            return false
        }
        return childPath.hasPrefix(parentPath + "/")
    }
}
