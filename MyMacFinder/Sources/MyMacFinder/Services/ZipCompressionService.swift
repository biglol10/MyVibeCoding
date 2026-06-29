import Foundation
import ZIPFoundation

public protocol ZipCompressing: Sendable {
    func compress(
        _ urls: [URL],
        to destinationFolder: URL,
        progress: FileOperationProgressReporter?
    ) async throws -> FileOperationResult
}

public extension ZipCompressing {
    func compress(_ urls: [URL], to destinationFolder: URL) async throws -> FileOperationResult {
        try await compress(urls, to: destinationFolder, progress: nil)
    }
}

public struct ZipCompressionService: ZipCompressing, @unchecked Sendable {
    private let fileManager: FileManager
    private let conflictResolver: any FileConflictResolving

    public init(
        fileManager: FileManager = .default,
        conflictResolver: any FileConflictResolving = DefaultFileConflictResolver()
    ) {
        self.fileManager = fileManager
        self.conflictResolver = conflictResolver
    }

    public func compress(
        _ urls: [URL],
        to destinationFolder: URL,
        progress: FileOperationProgressReporter? = nil
    ) async throws -> FileOperationResult {
        let sourceURLs = urls.map(\.standardizedFileURL)
        guard !sourceURLs.isEmpty else {
            throw ExplorerError.invalidPath("No items selected for compression.")
        }
        try await progress?.checkCancellation()
        try validateDestinationFolder(destinationFolder)
        try sourceURLs.forEach(validateSource)

        let proposedDestination = proposedArchiveURL(for: sourceURLs, in: destinationFolder)
        let resolution = try await resolvedArchiveDestination(
            sourceURLs: sourceURLs,
            proposedDestination: proposedDestination
        )
        guard let archiveURL = resolution.url else {
            return FileOperationResult(skippedURLs: sourceURLs)
        }

        try await createArchive(from: sourceURLs, to: archiveURL, progress: progress)
        return FileOperationResult(
            createdURLs: [archiveURL],
            replacedItems: resolution.replacedItem.map { [$0] } ?? []
        )
    }

    private struct ArchiveDestinationResolution {
        var url: URL?
        var replacedItem: FileTrashRecord?
    }

    private func validateDestinationFolder(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ExplorerError.pathDoesNotExist(url.path)
        }
        guard isDirectory.boolValue else {
            throw ExplorerError.notDirectory(url.path)
        }
    }

    private func validateSource(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw ExplorerError.pathDoesNotExist(url.path)
        }
    }

    private func proposedArchiveURL(for sourceURLs: [URL], in destinationFolder: URL) -> URL {
        let baseName: String
        if sourceURLs.count == 1, let source = sourceURLs.first {
            let stem = source.pathExtension.isEmpty
                ? source.lastPathComponent
                : source.deletingPathExtension().lastPathComponent
            baseName = stem.isEmpty ? "Archive" : stem
        } else {
            baseName = "Archive"
        }

        let proposed = destinationFolder
            .appendingPathComponent(baseName)
            .appendingPathExtension("zip")
            .standardizedFileURL

        if sourceURLs.contains(proposed) {
            return uniqueArchiveURL(for: proposed)
        }
        return proposed
    }

    private func resolvedArchiveDestination(
        sourceURLs: [URL],
        proposedDestination: URL
    ) async throws -> ArchiveDestinationResolution {
        guard fileManager.fileExists(atPath: proposedDestination.path) else {
            return ArchiveDestinationResolution(url: proposedDestination, replacedItem: nil)
        }

        let decision = try await conflictResolver.resolve(
            FileConflict(
                operation: .compress,
                sourceURL: sourceURLs[0],
                destinationURL: proposedDestination,
                itemIndex: 0,
                itemCount: sourceURLs.count
            )
        )

        switch decision {
        case .replace:
            return ArchiveDestinationResolution(
                url: proposedDestination,
                replacedItem: try trashExistingItem(at: proposedDestination)
            )
        case .keepBoth:
            return ArchiveDestinationResolution(url: uniqueArchiveURL(for: proposedDestination), replacedItem: nil)
        case .skip:
            return ArchiveDestinationResolution(url: nil, replacedItem: nil)
        case .cancel:
            throw FileOperationCancellation(operation: .compress)
        }
    }

    private func createArchive(
        from sourceURLs: [URL],
        to archiveURL: URL,
        progress: FileOperationProgressReporter?
    ) async throws {
        if sourceURLs.count == 1, let sourceURL = sourceURLs.first {
            try await progress?.checkCancellation()
            await progress?.update(
                phase: .writingArchive,
                currentItemName: sourceURL.lastPathComponent,
                completedUnitCount: 0,
                totalUnitCount: 1
            )
            try fileManager.zipItem(
                at: sourceURL,
                to: archiveURL,
                shouldKeepParent: true,
                compressionMethod: .deflate
            )
            await progress?.update(
                phase: .writingArchive,
                currentItemName: sourceURL.lastPathComponent,
                completedUnitCount: 1,
                totalUnitCount: 1
            )
            return
        }

        let stagingFolder = fileManager.temporaryDirectory
            .appendingPathComponent("MyMacFinderZipStaging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingFolder) }

        for (index, sourceURL) in sourceURLs.enumerated() {
            try await progress?.checkCancellation()
            await progress?.update(
                phase: .running,
                currentItemName: sourceURL.lastPathComponent,
                completedUnitCount: index,
                totalUnitCount: sourceURLs.count
            )
            let destination = uniqueStagingURL(for: sourceURL.lastPathComponent, in: stagingFolder)
            try fileManager.copyItem(at: sourceURL, to: destination)
            await progress?.update(
                phase: .running,
                currentItemName: sourceURL.lastPathComponent,
                completedUnitCount: index + 1,
                totalUnitCount: sourceURLs.count
            )
        }

        try await progress?.checkCancellation()
        await progress?.update(
            phase: .writingArchive,
            currentItemName: archiveURL.lastPathComponent,
            completedUnitCount: sourceURLs.count,
            totalUnitCount: sourceURLs.count
        )
        try fileManager.zipItem(
            at: stagingFolder,
            to: archiveURL,
            shouldKeepParent: false,
            compressionMethod: .deflate
        )
    }

    private func trashExistingItem(at url: URL) throws -> FileTrashRecord {
        var result: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &result)
        guard let result else {
            throw ExplorerError.readFailed("Item could not be moved to Trash: \(url.path)")
        }
        return FileTrashRecord(original: url, trashed: result as URL)
    }

    private func uniqueArchiveURL(for url: URL) -> URL {
        let parent = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        var candidate = parent.appendingPathComponent("\(stem) copy").appendingPathExtension("zip")
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(stem) copy \(index)").appendingPathExtension("zip")
            index += 1
        }
        return candidate.standardizedFileURL
    }

    private func uniqueStagingURL(for name: String, in folder: URL) -> URL {
        let candidate = folder.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        let stem = ext.isEmpty ? name : url.deletingPathExtension().lastPathComponent
        var index = 2
        var current: URL
        repeat {
            let currentName = ext.isEmpty ? "\(stem) copy \(index)" : "\(stem) copy \(index).\(ext)"
            current = folder.appendingPathComponent(currentName)
            index += 1
        } while fileManager.fileExists(atPath: current.path)
        return current
    }
}
