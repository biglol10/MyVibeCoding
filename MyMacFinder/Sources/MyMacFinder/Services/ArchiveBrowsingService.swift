import Foundation
import ZIPFoundation

public struct ArchiveEntry: Equatable, Sendable {
    public var location: ArchiveLocation
    public var name: String
    public var isDirectory: Bool
    public var size: Int64?
    public var modifiedAt: Date?

    public init(
        location: ArchiveLocation,
        name: String,
        isDirectory: Bool,
        size: Int64?,
        modifiedAt: Date?
    ) {
        self.location = location
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

public protocol ArchiveBrowsing: Sendable {
    func canOpen(_ url: URL) -> Bool
    func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry]
    func temporaryExtract(_ location: ArchiveLocation) async throws -> TemporaryArchiveArtifact
    func releaseTemporaryArtifact(_ artifact: TemporaryArchiveArtifact) async throws
    func scheduleTemporaryArtifactCleanupRetry(_ artifact: TemporaryArchiveArtifact) async throws
    func retainTemporaryArtifactForExternalOpen(_ artifact: TemporaryArchiveArtifact, openedAt: Date) async throws
    func validateTemporaryArtifactForHandoff(_ artifact: TemporaryArchiveArtifact) async throws
    func cleanupExpiredTemporaryArtifacts(now: Date, retentionInterval: TimeInterval) async throws
}

public extension ArchiveBrowsing {
    func releaseTemporaryArtifact(_ artifact: TemporaryArchiveArtifact) async throws {}

    func scheduleTemporaryArtifactCleanupRetry(_ artifact: TemporaryArchiveArtifact) async throws {}

    func retainTemporaryArtifactForExternalOpen(_ artifact: TemporaryArchiveArtifact, openedAt: Date) async throws {}

    func validateTemporaryArtifactForHandoff(_ artifact: TemporaryArchiveArtifact) async throws {}

    func cleanupExpiredTemporaryArtifacts(now: Date, retentionInterval: TimeInterval) async throws {}
}

public struct ArchiveBrowsingService: ArchiveBrowsing, @unchecked Sendable {
    typealias ExtractionHandler = (Archive, Entry, Progress, Consumer) throws -> Void

    private let artifactStore: ArchiveTemporaryArtifactStore
    private let extractionHandler: ExtractionHandler

    public init(
        fileManager: FileManager = .default,
        extractionRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderArchivePreview", isDirectory: true)
    ) {
        self.artifactStore = ArchiveTemporaryArtifactStore(
            fileManagerReference: ArchiveArtifactFileManagerReference(fileManager),
            extractionRoot: extractionRoot
        )
        self.extractionHandler = { archive, entry, progress, consumer in
            _ = try archive.extract(entry, progress: progress, consumer: consumer)
        }
    }

    init(
        fileManager: FileManager = .default,
        extractionRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderArchivePreview", isDirectory: true),
        cleanupRegistry: any ArchiveTemporaryArtifactCleanupPersisting = ArchiveTemporaryArtifactCleanupRegistry(),
        fileSystemHooks: ArchiveTemporaryFileSystemHooks = .none,
        extractionHandler: @escaping ExtractionHandler = { archive, entry, progress, consumer in
            _ = try archive.extract(entry, progress: progress, consumer: consumer)
        }
    ) {
        self.artifactStore = ArchiveTemporaryArtifactStore(
            fileManagerReference: ArchiveArtifactFileManagerReference(fileManager),
            extractionRoot: extractionRoot,
            cleanupRegistry: cleanupRegistry,
            fileSystemHooks: fileSystemHooks
        )
        self.extractionHandler = extractionHandler
    }

    public func canOpen(_ url: URL) -> Bool {
        url.pathExtension.localizedCaseInsensitiveCompare("zip") == .orderedSame
    }

    public func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry] {
        try await Task.detached(priority: .userInitiated) {
            let archive = try self.openArchive(location.archiveURL)
            let prefix = location.internalPath.isEmpty ? "" : "\(location.internalPath)/"
            var folders: [String: ArchiveEntry] = [:]
            var files: [ArchiveEntry] = []

            for entry in archive {
                guard ArchivePathSafety.isSafeEntryPath(entry.path) else {
                    continue
                }
                guard entry.path.hasPrefix(prefix) else {
                    continue
                }

                let remainder = String(entry.path.dropFirst(prefix.count))
                guard !remainder.isEmpty else {
                    continue
                }

                let components = remainder.split(separator: "/", omittingEmptySubsequences: true)
                guard let first = components.first else {
                    continue
                }

                let name = String(first)
                if !showHiddenFiles && name.hasPrefix(".") {
                    continue
                }

                if components.count > 1 {
                    let folderLocation = location.appending(name)
                    folders[name] = ArchiveEntry(
                        location: folderLocation,
                        name: name,
                        isDirectory: true,
                        size: nil,
                        modifiedAt: nil
                    )
                    continue
                }

                let entryLocation = location.appending(name)
                if entry.type == .directory {
                    folders[name] = ArchiveEntry(
                        location: entryLocation,
                        name: name,
                        isDirectory: true,
                        size: nil,
                        modifiedAt: entry.fileAttributes[.modificationDate] as? Date
                    )
                } else {
                    files.append(
                        ArchiveEntry(
                            location: entryLocation,
                            name: name,
                            isDirectory: false,
                            size: Int64(entry.uncompressedSize),
                            modifiedAt: entry.fileAttributes[.modificationDate] as? Date
                        )
                    )
                }
            }

            return Array(folders.values) + files
        }.value
    }

    public func temporaryExtract(_ location: ArchiveLocation) async throws -> TemporaryArchiveArtifact {
        try ArchivePathSafety.validateEntryPath(location.internalPath)
        let artifact = try await artifactStore.allocate(fileName: location.internalPath)
        let artifactState = ArchiveExtractionArtifactState(artifact)
        let progress = Progress(totalUnitCount: 0)

        do {
            try await withTaskCancellationHandler(operation: {
                try await Task.detached(priority: .userInitiated) { [self, progress] in
                    guard !progress.isCancelled else {
                        throw CancellationError()
                    }
                    let archive = try self.openArchive(location.archiveURL)
                    guard let entry = archive[location.internalPath], entry.type != .directory else {
                        throw ExplorerError.readFailed("ZIP entry cannot be previewed: \(location.displayPath)")
                    }
                    let output = try await self.artifactStore.openOutputFile(for: artifact)
                    let completedArtifact = artifact.recordingOutputIdentity(output.identity)
                    artifactState.update(completedArtifact)
                    do {
                        try self.extractionHandler(archive, entry, progress) { data in
                            try output.write(data)
                        }
                        try output.close()
                    } catch let extractionError {
                        do {
                            try output.close()
                        } catch let closeError {
                            throw ExplorerError.operationFailed(
                                "ZIP temporary extraction failed (\(extractionError.localizedDescription)) and output close "
                                    + "also failed: \(closeError.localizedDescription)"
                            )
                        }
                        throw extractionError
                    }
                    try await self.artifactStore.validatePublishedOutput(
                        completedArtifact
                    )
                    guard !progress.isCancelled else {
                        throw CancellationError()
                    }
                }.value
            }, onCancel: {
                progress.cancel()
            })
            return artifactState.value
        } catch {
            let extractionError: Error = progress.isCancelled || Task.isCancelled
                ? CancellationError()
                : error
            do {
                try await artifactStore.release(artifactState.value)
            } catch {
                if extractionError is CancellationError {
                    do {
                        try await artifactStore.scheduleCleanupRetry(artifactState.value)
                    } catch {
                        NSLog(
                            "MyMacFinder could not schedule cancelled archive preview cleanup for %@: %@",
                            artifact.ownerDirectoryURL.path,
                            error.localizedDescription
                        )
                    }
                    throw CancellationError()
                }
                throw ExplorerError.operationFailed(
                    "ZIP temporary extraction failed (\(extractionError.localizedDescription)) and temporary artifact cleanup "
                        + "failed at \(artifact.ownerDirectoryURL.path): \(error.localizedDescription)"
                )
            }
            throw extractionError
        }
    }

    public func releaseTemporaryArtifact(_ artifact: TemporaryArchiveArtifact) async throws {
        try await artifactStore.release(artifact)
    }

    public func scheduleTemporaryArtifactCleanupRetry(_ artifact: TemporaryArchiveArtifact) async throws {
        try await artifactStore.scheduleCleanupRetry(artifact)
    }

    public func retainTemporaryArtifactForExternalOpen(
        _ artifact: TemporaryArchiveArtifact,
        openedAt: Date
    ) async throws {
        try await artifactStore.registerExternalOpen(artifact, openedAt: openedAt)
    }

    public func validateTemporaryArtifactForHandoff(_ artifact: TemporaryArchiveArtifact) async throws {
        try await artifactStore.validateHandoff(artifact)
    }

    public func cleanupExpiredTemporaryArtifacts(
        now: Date,
        retentionInterval: TimeInterval
    ) async throws {
        try await artifactStore.cleanupExpired(now: now, retentionInterval: retentionInterval)
    }

    private func openArchive(_ url: URL) throws -> Archive {
        do {
            return try Archive(url: url, accessMode: .read)
        } catch {
            throw ExplorerError.readFailed("ZIP archive could not be read: \(url.path)")
        }
    }
}

private final class ArchiveExtractionArtifactState: @unchecked Sendable {
    private let lock = NSLock()
    private var artifact: TemporaryArchiveArtifact

    init(_ artifact: TemporaryArchiveArtifact) {
        self.artifact = artifact
    }

    var value: TemporaryArchiveArtifact {
        lock.withLock { artifact }
    }

    func update(_ artifact: TemporaryArchiveArtifact) {
        lock.withLock {
            self.artifact = artifact
        }
    }
}
