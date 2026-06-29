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

    public init(
        fileManager: FileManager = .default,
        conflictResolver: any FileConflictResolving = DefaultFileConflictResolver()
    ) {
        self.fileManager = fileManager
        self.conflictResolver = conflictResolver
    }

    public func extract(
        _ zipURLs: [URL],
        to destinationFolder: URL,
        progress: FileOperationProgressReporter? = nil
    ) async throws -> FileOperationResult {
        var createdURLs: [URL] = []
        var replacedItems: [FileTrashRecord] = []
        var skippedURLs: [URL] = []

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
                throw ExplorerError.readFailed("ZIP archive could not be read: \(zipURL.path)")
            }

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

            try fileManager.createDirectory(at: extractionFolder, withIntermediateDirectories: true)
            let entries = Array(archive)
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
                let destination = extractionFolder.appendingPathComponent(entry.path)
                guard isContained(destination, in: extractionFolder) else {
                    throw ExplorerError.readFailed("ZIP entry attempted to extract outside destination: \(entry.path)")
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

            createdURLs.append(extractionFolder.standardizedFileURL)
            if let replacedItem = resolution.replacedItem {
                replacedItems.append(replacedItem)
            }
        }

        return FileOperationResult(
            createdURLs: createdURLs,
            replacedItems: replacedItems,
            skippedURLs: skippedURLs
        )
    }

    private struct ExtractionResolution {
        var url: URL?
        var replacedItem: FileTrashRecord?
    }

    private func resolvedExtractionFolder(
        zipURL: URL,
        proposedFolder: URL,
        index: Int,
        count: Int
    ) async throws -> ExtractionResolution {
        guard fileManager.fileExists(atPath: proposedFolder.path) else {
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
            let replacedItem = try trashExistingItem(at: proposedFolder)
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

    private func trashExistingItem(at url: URL) throws -> FileTrashRecord {
        var result: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &result)
        guard let result else {
            throw ExplorerError.readFailed("Item could not be moved to Trash: \(url.path)")
        }
        return FileTrashRecord(original: url, trashed: result as URL)
    }

    private func uniqueURL(in parent: URL, baseName: String) -> URL {
        var candidate = parent.appendingPathComponent("\(baseName) copy", isDirectory: true)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(baseName) copy \(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }

    private func isContained(_ url: URL, in folder: URL) -> Bool {
        let folderPath = folder.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        return targetPath == folderPath || targetPath.hasPrefix(folderPath + "/")
    }
}
