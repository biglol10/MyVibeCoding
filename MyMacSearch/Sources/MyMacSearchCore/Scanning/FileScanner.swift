import Foundation

public enum ScanIssueCategory: String, Equatable, Sendable {
    case permissionDenied
    case missing
    case metadata
    case enumeration
}

public struct ScanIssue: Equatable, Sendable {
    public let path: String
    public let category: ScanIssueCategory
    public let message: String

    public init(path: String, category: ScanIssueCategory, message: String) {
        self.path = path
        self.category = category
        self.message = message
    }
}

public struct ScanSummary: Equatable, Sendable {
    public let scannedCount: Int
    public let skippedCount: Int
    public let permissionDeniedCount: Int
    public let issues: [ScanIssue]
    public let completed: Bool
}

public enum FileScanError: Error, LocalizedError, Equatable, Sendable {
    case rootPermissionDenied(String)
    case rootUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .rootPermissionDenied(let path):
            return "Permission denied for indexing scope: \(path)"
        case .rootUnavailable(let path):
            return "Indexing scope is unavailable: \(path)"
        }
    }
}

public struct FileScanner: Sendable {
    public typealias BatchHandler = @Sendable ([IndexedEntry]) async -> Void
    public typealias ProgressHandler = @Sendable (IndexProgress) async -> Void

    private let metadataClient: any FileMetadataClient
    private let policy: IndexingPolicy
    private let batchSize: Int

    public init(
        metadataClient: any FileMetadataClient,
        policy: IndexingPolicy,
        batchSize: Int = 1_000
    ) {
        self.metadataClient = metadataClient
        self.policy = policy
        self.batchSize = max(1, batchSize)
    }

    public func scan(
        scope: IndexScope,
        generation: Int64,
        onBatch: @escaping BatchHandler,
        onProgress: @escaping ProgressHandler
    ) async throws -> ScanSummary {
        try Task.checkCancellation()
        let rootURL = URL(fileURLWithPath: scope.rootPath, isDirectory: true).standardizedFileURL
        let rootMetadata: FileMetadata
        do {
            rootMetadata = try await metadataClient.metadata(at: rootURL)
        } catch FileMetadataClientError.permissionDenied {
            throw FileScanError.rootPermissionDenied(rootURL.path)
        } catch {
            throw FileScanError.rootUnavailable(rootURL.path)
        }

        guard rootMetadata.isDirectory else {
            throw FileScanError.rootUnavailable(rootURL.path)
        }
        guard policy.decision(for: rootMetadata) == .indexAndDescend else {
            return ScanSummary(
                scannedCount: 0,
                skippedCount: 0,
                permissionDeniedCount: 0,
                issues: [],
                completed: true
            )
        }

        var directories = [rootURL]
        var directoryIndex = 0
        var batch: [IndexedEntry] = []
        var progress = IndexProgress(queuedDirectories: 1)
        var issues: [ScanIssue] = []

        while directoryIndex < directories.count {
            try Task.checkCancellation()
            let directoryURL = directories[directoryIndex]
            directoryIndex += 1
            progress.queuedDirectories = directories.count - directoryIndex
            progress.currentPath = directoryURL.path

            let children: [URL]
            do {
                children = try await metadataClient.children(of: directoryURL)
            } catch {
                Self.record(
                    error: error,
                    path: directoryURL.path,
                    progress: &progress,
                    issues: &issues,
                    defaultCategory: .enumeration
                )
                progress.processedDirectories += 1
                await onProgress(progress)
                continue
            }

            for childURL in children {
                try Task.checkCancellation()
                let metadata: FileMetadata
                do {
                    metadata = try await metadataClient.metadata(at: childURL)
                } catch {
                    Self.record(
                        error: error,
                        path: childURL.path,
                        progress: &progress,
                        issues: &issues,
                        defaultCategory: .metadata
                    )
                    continue
                }

                let decision = policy.decision(for: metadata)
                switch decision {
                case .exclude:
                    continue
                case .indexOnly, .indexAndDescend:
                    let entry = Self.makeEntry(
                        metadata: metadata,
                        scopeID: scope.id,
                        generation: generation
                    )
                    batch.append(entry)
                    progress.scannedCount += 1
                    if decision == .indexAndDescend {
                        directories.append(URL(fileURLWithPath: metadata.path, isDirectory: true))
                        progress.queuedDirectories += 1
                    }
                    if batch.count >= batchSize {
                        try Task.checkCancellation()
                        await onBatch(batch)
                        batch.removeAll(keepingCapacity: true)
                    }
                }
            }

            progress.processedDirectories += 1
            progress.queuedDirectories = directories.count - directoryIndex
            await onProgress(progress)
        }

        if !batch.isEmpty {
            try Task.checkCancellation()
            await onBatch(batch)
        }
        try Task.checkCancellation()

        return ScanSummary(
            scannedCount: progress.scannedCount,
            skippedCount: progress.skippedCount,
            permissionDeniedCount: progress.permissionDeniedCount,
            issues: issues,
            completed: true
        )
    }

    private static func makeEntry(
        metadata: FileMetadata,
        scopeID: String,
        generation: Int64
    ) -> IndexedEntry {
        let url = URL(fileURLWithPath: metadata.path)
        return IndexedEntry(
            scopeID: scopeID,
            path: metadata.path,
            parentPath: url.deletingLastPathComponent().path,
            name: metadata.name,
            fileExtension: url.pathExtension,
            kind: FileKindClassifier.kind(
                name: metadata.name,
                isDirectory: metadata.isDirectory,
                isPackage: metadata.isPackage
            ),
            sizeBytes: metadata.sizeBytes,
            modifiedAt: metadata.modifiedAt,
            isDirectory: metadata.isDirectory,
            isSymlink: metadata.isSymlink,
            isPackage: metadata.isPackage,
            isHidden: metadata.isHidden,
            deviceID: metadata.deviceID,
            inode: metadata.inode,
            scanGeneration: generation
        )
    }

    private static func record(
        error: Error,
        path: String,
        progress: inout IndexProgress,
        issues: inout [ScanIssue],
        defaultCategory: ScanIssueCategory
    ) {
        progress.skippedCount += 1
        let category: ScanIssueCategory
        if case FileMetadataClientError.permissionDenied = error {
            category = .permissionDenied
            progress.permissionDeniedCount += 1
        } else if case FileMetadataClientError.missing = error {
            category = .missing
        } else {
            category = defaultCategory
        }
        if issues.count < 500 {
            issues.append(
                ScanIssue(path: path, category: category, message: error.localizedDescription)
            )
        }
    }
}
