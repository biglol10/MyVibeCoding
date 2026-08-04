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

        let outputStagingDirectory = uniqueOutputStagingDirectory(in: destinationFolder)
        let stagedArchiveURL = outputStagingDirectory.appendingPathComponent(archiveURL.lastPathComponent)
        var outputStagingIdentity: FileSystemPathIdentity.FileSystemEntryIdentity?
        var stagedArchiveIdentity: FileSystemPathIdentity.FileSystemEntryIdentity?
        do {
            try fileManager.createDirectory(
                at: outputStagingDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            guard let createdStagingIdentity = FileSystemPathIdentity.entryIdentity(outputStagingDirectory) else {
                throw ExplorerError.operationFailed(
                    "Compression staging directory identity is unavailable: \(outputStagingDirectory.path)"
                )
            }
            outputStagingIdentity = createdStagingIdentity
            try await createArchive(from: sourceURLs, to: stagedArchiveURL, progress: progress)
            guard let createdArchiveIdentity = FileSystemPathIdentity.entryIdentity(stagedArchiveURL) else {
                throw ExplorerError.operationFailed(
                    "Compression staging archive identity is unavailable: \(stagedArchiveURL.path)"
                )
            }
            stagedArchiveIdentity = createdArchiveIdentity
            try fileManager.moveItem(at: stagedArchiveURL, to: archiveURL)
        } catch {
            let operationError = archiveOperationError(error)
            var rollbackFailures: [String] = []
            if let outputStagingIdentity {
                do {
                    try cleanupOwnedOutputStagingDirectory(
                        outputStagingDirectory,
                        expectedDirectoryIdentity: outputStagingIdentity,
                        stagedArchive: stagedArchiveURL,
                        expectedArchiveIdentity: stagedArchiveIdentity
                    )
                } catch {
                    rollbackFailures.append(error.localizedDescription)
                }
            } else if FileSystemPathIdentity.entryExists(outputStagingDirectory) {
                rollbackFailures.append(
                    "Compression staging ownership could not be verified: \(outputStagingDirectory.path)"
                )
            }
            do {
                try rollbackReplacement(resolution.replacedItem)
            } catch {
                rollbackFailures.append(error.localizedDescription)
            }
            if !rollbackFailures.isEmpty {
                throw ExplorerError.operationFailed(
                    "Compression failed (\(operationError.localizedDescription)) and rollback was incomplete: "
                        + rollbackFailures.joined(separator: "; ")
                )
            }
            throw operationError
        }
        guard let outputStagingIdentity else {
            throw ExplorerError.operationFailed(
                "Compression staging directory identity was lost before commit: \(outputStagingDirectory.path)"
            )
        }
        removeCommittedStagingDirectory(
            outputStagingDirectory,
            expectedIdentity: outputStagingIdentity
        )
        var result = FileOperationResult(
            createdURLs: [archiveURL],
            replacedItems: resolution.replacedItem.map { [$0.record] } ?? []
        )
        if let stagedArchiveIdentity {
            result.undoSourceIdentities[archiveURL.standardizedFileURL] = stagedArchiveIdentity
        }
        if let replacedItem = resolution.replacedItem {
            result.undoSourceIdentities[replacedItem.record.trashed] = replacedItem.trashedIdentity
        }
        return result
    }

    private struct ArchiveDestinationResolution {
        var url: URL?
        var replacedItem: FileSystemPathIdentity.TrackedTrashRecord?
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
        guard let expectedDestinationIdentity = FileSystemPathIdentity.entryIdentity(proposedDestination) else {
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
            try FileSystemPathIdentity.requireUnchangedEntry(
                at: proposedDestination,
                expectedIdentity: expectedDestinationIdentity,
                operation: "Compression"
            )
            return ArchiveDestinationResolution(
                url: proposedDestination,
                replacedItem: try trashExistingItem(
                    at: proposedDestination,
                    expectedIdentity: expectedDestinationIdentity
                )
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
        try fileManager.createDirectory(
            at: stagingFolder,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        guard let stagingIdentity = FileSystemPathIdentity.entryIdentity(stagingFolder) else {
            throw ExplorerError.operationFailed(
                "Compression source staging identity is unavailable: \(stagingFolder.path)"
            )
        }
        do {
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
        } catch {
            do {
                try cleanupOwnedStagingDirectory(stagingFolder, expectedIdentity: stagingIdentity)
            } catch let cleanupError {
                throw ExplorerError.operationFailed(
                    "Compression failed (\(error.localizedDescription)) and temporary staging cleanup failed "
                        + "at \(stagingFolder.path): \(cleanupError.localizedDescription)"
                )
            }
            throw error
        }
        try cleanupOwnedStagingDirectory(stagingFolder, expectedIdentity: stagingIdentity)
    }

    private func trashExistingItem(
        at url: URL,
        expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity? = nil
    ) throws -> FileSystemPathIdentity.TrackedTrashRecord {
        try FileSystemPathIdentity.moveToTrashSafely(
            at: url,
            expectedIdentity: expectedIdentity,
            fileManager: fileManager,
            operation: "Compression replace",
            trashItem: trashItem
        )
    }

    private func rollbackReplacement(_ trackedRecord: FileSystemPathIdentity.TrackedTrashRecord?) throws {
        var failures: [String] = []
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

    private func cleanupOwnedStagingDirectory(
        _ url: URL,
        expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity
    ) throws {
        guard let currentIdentity = FileSystemPathIdentity.entryIdentity(url) else {
            return
        }
        guard currentIdentity == expectedIdentity else {
            throw ExplorerError.operationFailed("Compression staging directory identity changed: \(url.path)")
        }
        try fileManager.removeItem(at: url)
    }

    private func cleanupOwnedOutputStagingDirectory(
        _ directory: URL,
        expectedDirectoryIdentity: FileSystemPathIdentity.FileSystemEntryIdentity,
        stagedArchive: URL,
        expectedArchiveIdentity: FileSystemPathIdentity.FileSystemEntryIdentity?
    ) throws {
        guard let currentDirectoryIdentity = FileSystemPathIdentity.entryIdentity(directory) else {
            return
        }
        guard currentDirectoryIdentity == expectedDirectoryIdentity else {
            throw ExplorerError.operationFailed("Compression staging directory identity changed: \(directory.path)")
        }

        let childNames = try fileManager.contentsOfDirectory(atPath: directory.path)
        if let expectedArchiveIdentity {
            guard childNames.allSatisfy({ $0 == stagedArchive.lastPathComponent }) else {
                throw ExplorerError.operationFailed(
                    "Compression staging directory contains an unrelated entry: \(directory.path)"
                )
            }
            if let currentArchiveIdentity = FileSystemPathIdentity.entryIdentity(stagedArchive),
               currentArchiveIdentity != expectedArchiveIdentity {
                throw ExplorerError.operationFailed(
                    "Compression staging archive identity changed: \(stagedArchive.path)"
                )
            }
        } else if !childNames.isEmpty {
            throw ExplorerError.operationFailed(
                "Compression staging archive ownership could not be verified before cleanup: \(directory.path)"
            )
        }
        try fileManager.removeItem(at: directory)
    }

    private func removeCommittedStagingDirectory(
        _ url: URL,
        expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity
    ) {
        guard FileSystemPathIdentity.entryIdentity(url) == expectedIdentity else {
            NSLog("MyMacFinder left a changed compression staging directory untouched: %@", url.path)
            return
        }
        do {
            guard try fileManager.contentsOfDirectory(atPath: url.path).isEmpty else {
                NSLog("MyMacFinder left a non-empty compression staging directory untouched: %@", url.path)
                return
            }
            try fileManager.removeItem(at: url)
        } catch {
            NSLog("MyMacFinder could not remove compression staging directory %@: %@", url.path, error.localizedDescription)
        }
    }

    private func uniqueOutputStagingDirectory(in destinationFolder: URL) -> URL {
        var candidate: URL
        repeat {
            candidate = destinationFolder.appendingPathComponent(
                ".MyMacFinder-compress-\(UUID().uuidString)",
                isDirectory: true
            )
        } while FileSystemPathIdentity.entryExists(candidate)
        return candidate
    }

    private func uniqueArchiveURL(for url: URL) -> URL {
        let parent = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        var candidate = parent.appendingPathComponent("\(stem) copy").appendingPathExtension("zip")
        var index = 2
        while FileSystemPathIdentity.entryExists(candidate) {
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
