import Foundation

final class ArchiveArtifactFileManagerReference: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}

struct PendingArchiveTemporaryArtifactCleanup: Codable, Sendable {
    let urlPath: String
    let ownerDirectoryPath: String
    let ownerIdentifier: UUID
    let expectedOwnerDevice: UInt64
    let expectedOwnerInode: UInt64
    let expectedOwnerGeneration: UInt32
    let expectedOwnerMode: UInt32
    let expectedOutputDevice: UInt64?
    let expectedOutputInode: UInt64?
    let expectedOutputGeneration: UInt32?
    let expectedOutputMode: UInt32?

    init(_ artifact: TemporaryArchiveArtifact) {
        self.urlPath = artifact.url.path
        self.ownerDirectoryPath = artifact.ownerDirectoryURL.path
        self.ownerIdentifier = artifact.ownerIdentifier
        self.expectedOwnerDevice = artifact.expectedOwnerIdentity.device
        self.expectedOwnerInode = artifact.expectedOwnerIdentity.inode
        self.expectedOwnerGeneration = artifact.expectedOwnerIdentity.generation
        self.expectedOwnerMode = artifact.expectedOwnerIdentity.mode
        self.expectedOutputDevice = artifact.expectedOutputIdentity?.device
        self.expectedOutputInode = artifact.expectedOutputIdentity?.inode
        self.expectedOutputGeneration = artifact.expectedOutputIdentity?.generation
        self.expectedOutputMode = artifact.expectedOutputIdentity?.mode
    }

    var artifact: TemporaryArchiveArtifact {
        TemporaryArchiveArtifact(
            url: URL(fileURLWithPath: urlPath),
            ownerDirectoryURL: URL(fileURLWithPath: ownerDirectoryPath, isDirectory: true),
            ownerIdentifier: ownerIdentifier,
            expectedOwnerIdentity: FileSystemPathIdentity.FileSystemEntryIdentity(
                device: expectedOwnerDevice,
                inode: expectedOwnerInode,
                generation: expectedOwnerGeneration,
                mode: expectedOwnerMode
            ),
            expectedOutputIdentity: expectedOutputIdentity
        )
    }

    private var expectedOutputIdentity: FileSystemPathIdentity.FileSystemEntryIdentity? {
        guard let expectedOutputDevice,
              let expectedOutputInode,
              let expectedOutputGeneration,
              let expectedOutputMode else {
            return nil
        }
        return FileSystemPathIdentity.FileSystemEntryIdentity(
            device: expectedOutputDevice,
            inode: expectedOutputInode,
            generation: expectedOutputGeneration,
            mode: expectedOutputMode
        )
    }
}

struct RetainedArchiveTemporaryArtifact: Codable, Sendable {
    let urlPath: String
    let ownerDirectoryPath: String
    let ownerIdentifier: UUID
    let expectedOwnerDevice: UInt64
    let expectedOwnerInode: UInt64
    let expectedOwnerGeneration: UInt32
    let expectedOwnerMode: UInt32
    let expectedOutputDevice: UInt64?
    let expectedOutputInode: UInt64?
    let expectedOutputGeneration: UInt32?
    let expectedOutputMode: UInt32?
    let openedAt: Date

    init(_ artifact: TemporaryArchiveArtifact, openedAt: Date) {
        self.urlPath = artifact.url.path
        self.ownerDirectoryPath = artifact.ownerDirectoryURL.path
        self.ownerIdentifier = artifact.ownerIdentifier
        self.expectedOwnerDevice = artifact.expectedOwnerIdentity.device
        self.expectedOwnerInode = artifact.expectedOwnerIdentity.inode
        self.expectedOwnerGeneration = artifact.expectedOwnerIdentity.generation
        self.expectedOwnerMode = artifact.expectedOwnerIdentity.mode
        self.expectedOutputDevice = artifact.expectedOutputIdentity?.device
        self.expectedOutputInode = artifact.expectedOutputIdentity?.inode
        self.expectedOutputGeneration = artifact.expectedOutputIdentity?.generation
        self.expectedOutputMode = artifact.expectedOutputIdentity?.mode
        self.openedAt = openedAt
    }

    var artifact: TemporaryArchiveArtifact {
        TemporaryArchiveArtifact(
            url: URL(fileURLWithPath: urlPath),
            ownerDirectoryURL: URL(fileURLWithPath: ownerDirectoryPath, isDirectory: true),
            ownerIdentifier: ownerIdentifier,
            expectedOwnerIdentity: FileSystemPathIdentity.FileSystemEntryIdentity(
                device: expectedOwnerDevice,
                inode: expectedOwnerInode,
                generation: expectedOwnerGeneration,
                mode: expectedOwnerMode
            ),
            expectedOutputIdentity: expectedOutputIdentity
        )
    }

    private var expectedOutputIdentity: FileSystemPathIdentity.FileSystemEntryIdentity? {
        guard let expectedOutputDevice,
              let expectedOutputInode,
              let expectedOutputGeneration,
              let expectedOutputMode else {
            return nil
        }
        return FileSystemPathIdentity.FileSystemEntryIdentity(
            device: expectedOutputDevice,
            inode: expectedOutputInode,
            generation: expectedOutputGeneration,
            mode: expectedOutputMode
        )
    }
}

protocol ArchiveTemporaryArtifactCleanupPersisting: Sendable {
    func load() throws -> [PendingArchiveTemporaryArtifactCleanup]
    func save(_ records: [PendingArchiveTemporaryArtifactCleanup]) throws
}

final class ArchiveTemporaryArtifactCleanupRegistry: ArchiveTemporaryArtifactCleanupPersisting, @unchecked Sendable {
    private static let key = "MyMacFinder.pendingArchiveTemporaryArtifactCleanup"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() throws -> [PendingArchiveTemporaryArtifactCleanup] {
        guard let data = userDefaults.data(forKey: Self.key) else {
            return []
        }
        return try JSONDecoder().decode([PendingArchiveTemporaryArtifactCleanup].self, from: data)
    }

    func save(_ records: [PendingArchiveTemporaryArtifactCleanup]) throws {
        guard !records.isEmpty else {
            userDefaults.removeObject(forKey: Self.key)
            return
        }
        userDefaults.set(try JSONEncoder().encode(records), forKey: Self.key)
    }
}

protocol ArchiveTemporaryArtifactRetentionPersisting: Sendable {
    func load() throws -> [RetainedArchiveTemporaryArtifact]
    func save(_ records: [RetainedArchiveTemporaryArtifact]) throws
}

final class ArchiveTemporaryArtifactRetentionRegistry: ArchiveTemporaryArtifactRetentionPersisting, @unchecked Sendable {
    private static let key = "MyMacFinder.retainedArchiveTemporaryArtifacts"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() throws -> [RetainedArchiveTemporaryArtifact] {
        guard let data = userDefaults.data(forKey: Self.key) else {
            return []
        }
        return try JSONDecoder().decode([RetainedArchiveTemporaryArtifact].self, from: data)
    }

    func save(_ records: [RetainedArchiveTemporaryArtifact]) throws {
        guard !records.isEmpty else {
            userDefaults.removeObject(forKey: Self.key)
            return
        }
        userDefaults.set(try JSONEncoder().encode(records), forKey: Self.key)
    }
}

public struct TemporaryArchiveArtifact: Equatable, Sendable {
    public let url: URL
    let ownerDirectoryURL: URL
    let ownerIdentifier: UUID
    let expectedOwnerIdentity: FileSystemPathIdentity.FileSystemEntryIdentity
    let expectedOutputIdentity: FileSystemPathIdentity.FileSystemEntryIdentity?

    init(
        url: URL,
        ownerDirectoryURL: URL,
        ownerIdentifier: UUID,
        expectedOwnerIdentity: FileSystemPathIdentity.FileSystemEntryIdentity,
        expectedOutputIdentity: FileSystemPathIdentity.FileSystemEntryIdentity? = nil
    ) {
        self.url = url
        self.ownerDirectoryURL = ownerDirectoryURL
        self.ownerIdentifier = ownerIdentifier
        self.expectedOwnerIdentity = expectedOwnerIdentity
        self.expectedOutputIdentity = expectedOutputIdentity
    }

    func recordingOutputIdentity(
        _ identity: FileSystemPathIdentity.FileSystemEntryIdentity
    ) -> TemporaryArchiveArtifact {
        TemporaryArchiveArtifact(
            url: url,
            ownerDirectoryURL: ownerDirectoryURL,
            ownerIdentifier: ownerIdentifier,
            expectedOwnerIdentity: expectedOwnerIdentity,
            expectedOutputIdentity: identity
        )
    }
}

actor ArchiveTemporaryArtifactStore {
    private struct ExternalOpenRecord: Sendable {
        let artifact: TemporaryArchiveArtifact
        let openedAt: Date
    }

    private let extractionRoot: URL
    private let temporaryFileSystem: ArchiveTemporaryFileSystem
    private let cleanupRegistry: any ArchiveTemporaryArtifactCleanupPersisting
    private let retentionRegistry: any ArchiveTemporaryArtifactRetentionPersisting
    private let cleanupRegistryIsUsable: Bool
    private let retentionRegistryIsUsable: Bool
    private let cleanupRegistryLoadFailure: String?
    private let retentionRegistryLoadFailure: String?
    private var externalOpenRecords: [UUID: ExternalOpenRecord] = [:]
    private var pendingCleanupRecords: [UUID: PendingArchiveTemporaryArtifactCleanup]

    init(
        fileManager: FileManager = .default,
        extractionRoot: URL,
        cleanupRegistry: any ArchiveTemporaryArtifactCleanupPersisting = ArchiveTemporaryArtifactCleanupRegistry(),
        retentionRegistry: any ArchiveTemporaryArtifactRetentionPersisting = ArchiveTemporaryArtifactRetentionRegistry(),
        fileSystemHooks: ArchiveTemporaryFileSystemHooks = .none
    ) {
        self.init(
            fileManagerReference: ArchiveArtifactFileManagerReference(fileManager),
            extractionRoot: extractionRoot,
            cleanupRegistry: cleanupRegistry,
            retentionRegistry: retentionRegistry,
            fileSystemHooks: fileSystemHooks
        )
    }

    init(
        fileManagerReference: ArchiveArtifactFileManagerReference,
        extractionRoot: URL,
        cleanupRegistry: any ArchiveTemporaryArtifactCleanupPersisting = ArchiveTemporaryArtifactCleanupRegistry(),
        retentionRegistry: any ArchiveTemporaryArtifactRetentionPersisting = ArchiveTemporaryArtifactRetentionRegistry(),
        fileSystemHooks: ArchiveTemporaryFileSystemHooks = .none
    ) {
        self.extractionRoot = FileSystemPathIdentity.canonicalDirectory(extractionRoot)
        self.temporaryFileSystem = ArchiveTemporaryFileSystem(
            fileManager: fileManagerReference.value,
            hooks: fileSystemHooks
        )
        self.cleanupRegistry = cleanupRegistry
        self.retentionRegistry = retentionRegistry
        do {
            var loadedRecords: [UUID: PendingArchiveTemporaryArtifactCleanup] = [:]
            for record in try cleanupRegistry.load() {
                guard loadedRecords.updateValue(record, forKey: record.ownerIdentifier) == nil else {
                    throw ExplorerError.operationFailed(
                        "Pending archive preview cleanup registry contains duplicate owner identifiers."
                    )
                }
            }
            self.pendingCleanupRecords = loadedRecords
            self.cleanupRegistryIsUsable = true
            self.cleanupRegistryLoadFailure = nil
        } catch {
            self.pendingCleanupRecords = [:]
            self.cleanupRegistryIsUsable = false
            self.cleanupRegistryLoadFailure = error.localizedDescription
            NSLog("MyMacFinder could not load pending archive preview cleanup records: %@", error.localizedDescription)
        }
        do {
            var loadedRecords: [UUID: ExternalOpenRecord] = [:]
            for record in try retentionRegistry.load() {
                guard loadedRecords.updateValue(
                    ExternalOpenRecord(artifact: record.artifact, openedAt: record.openedAt),
                    forKey: record.ownerIdentifier
                ) == nil else {
                    throw ExplorerError.operationFailed(
                        "Archive preview retention registry contains duplicate owner identifiers."
                    )
                }
            }
            self.externalOpenRecords = loadedRecords
            self.retentionRegistryIsUsable = true
            self.retentionRegistryLoadFailure = nil
        } catch {
            self.externalOpenRecords = [:]
            self.retentionRegistryIsUsable = false
            self.retentionRegistryLoadFailure = error.localizedDescription
            NSLog("MyMacFinder could not load retained archive preview artifacts: %@", error.localizedDescription)
        }
    }

    func allocate(fileName: String, identifier: UUID = UUID()) throws -> TemporaryArchiveArtifact {
        let leafName = try sanitizedLeafName(from: fileName)
        return try temporaryFileSystem.allocate(
            extractionRoot: extractionRoot,
            identifier: identifier,
            leafName: leafName
        )
    }

    func openOutputFile(for artifact: TemporaryArchiveArtifact) throws -> ArchiveTemporaryOutputFile {
        try temporaryFileSystem.openOutputFile(extractionRoot: extractionRoot, artifact: artifact)
    }

    func validatePublishedOutput(_ artifact: TemporaryArchiveArtifact) throws {
        try temporaryFileSystem.validatePublishedOutput(
            extractionRoot: extractionRoot,
            artifact: artifact
        )
    }

    func validateHandoff(_ artifact: TemporaryArchiveArtifact) throws {
        try temporaryFileSystem.validatePublishedOutput(extractionRoot: extractionRoot, artifact: artifact)
    }

    func release(_ artifact: TemporaryArchiveArtifact) throws {
        try temporaryFileSystem.removeOwner(extractionRoot: extractionRoot, artifact: artifact)
        externalOpenRecords.removeValue(forKey: artifact.ownerIdentifier)
        saveExternalOpenRecords()
        removePendingCleanupRecord(for: artifact.ownerIdentifier)
    }

    func registerExternalOpen(_ artifact: TemporaryArchiveArtifact, openedAt: Date) throws {
        guard retentionRegistryIsUsable else {
            throw ExplorerError.operationFailed("Archive preview retention registry is unavailable.")
        }
        try temporaryFileSystem.validateOwnership(extractionRoot: extractionRoot, artifact: artifact)
        var updatedRecords = externalOpenRecords
        updatedRecords[artifact.ownerIdentifier] = ExternalOpenRecord(
            artifact: artifact,
            openedAt: openedAt
        )
        try saveExternalOpenRecords(updatedRecords)
        externalOpenRecords = updatedRecords
    }

    func cleanupExpired(now: Date, retentionInterval: TimeInterval) throws {
        var phaseFailures: [String] = []
        do {
            try retryPendingCleanup()
        } catch {
            phaseFailures.append("pending cleanup phase: \(error.localizedDescription)")
        }

        if retentionRegistryIsUsable {
            let expiredRecords = externalOpenRecords.values.filter {
                now.timeIntervalSince($0.openedAt) >= retentionInterval
            }
            var retentionFailures: [String] = []
            for record in expiredRecords {
                guard FileSystemPathIdentity.entryIdentity(record.artifact.ownerDirectoryURL) != nil else {
                    externalOpenRecords.removeValue(forKey: record.artifact.ownerIdentifier)
                    saveExternalOpenRecords()
                    continue
                }
                do {
                    try release(record.artifact)
                } catch {
                    retentionFailures.append(
                        "\(record.artifact.ownerDirectoryURL.path): \(error.localizedDescription)"
                    )
                }
            }
            if !retentionFailures.isEmpty {
                phaseFailures.append("retention cleanup phase: \(retentionFailures.joined(separator: "; "))")
            }
        } else {
            let loadFailure = retentionRegistryLoadFailure.map { " Load failure: \($0)" } ?? ""
            phaseFailures.append("retention cleanup phase: Archive preview retention registry is unavailable.\(loadFailure)")
        }

        guard phaseFailures.isEmpty else {
            throw ExplorerError.operationFailed(
                "Archive preview cleanup completed with failures: \(phaseFailures.joined(separator: " | "))"
            )
        }
    }

    func scheduleCleanupRetry(_ artifact: TemporaryArchiveArtifact) throws {
        guard cleanupRegistryIsUsable else {
            let loadFailure = cleanupRegistryLoadFailure.map { " Load failure: \($0)" } ?? ""
            throw ExplorerError.operationFailed("Archive preview cleanup registry is unavailable.\(loadFailure)")
        }
        let record = PendingArchiveTemporaryArtifactCleanup(artifact)
        var updatedRecords = pendingCleanupRecords
        updatedRecords[record.ownerIdentifier] = record
        try cleanupRegistry.save(Array(updatedRecords.values))
        pendingCleanupRecords = updatedRecords
    }

    func retryPendingCleanup() throws {
        guard cleanupRegistryIsUsable else {
            throw ExplorerError.operationFailed("Archive preview cleanup registry is unavailable.")
        }
        var failures: [String] = []
        for record in pendingCleanupRecords.values {
            guard FileSystemPathIdentity.entryIdentity(record.artifact.ownerDirectoryURL) != nil else {
                removePendingCleanupRecord(for: record.ownerIdentifier)
                continue
            }
            do {
                try release(record.artifact)
            } catch {
                failures.append("\(record.ownerDirectoryPath): \(error.localizedDescription)")
            }
        }
        guard failures.isEmpty else {
            throw ExplorerError.operationFailed(
                "Archive preview cleanup retry failed: \(failures.joined(separator: "; "))"
            )
        }
    }

    private func sanitizedLeafName(from fileName: String) throws -> String {
        let normalized = fileName.replacingOccurrences(of: "\\", with: "/")
        guard normalized != "/", normalized != ".", normalized != ".." else {
            throw ExplorerError.archiveFailed("ZIP entry has an invalid preview filename: \(fileName)")
        }
        let leafName = normalized.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        guard !leafName.isEmpty, leafName != ".", leafName != ".." else {
            throw ExplorerError.archiveFailed("ZIP entry has an invalid preview filename: \(fileName)")
        }
        return leafName
    }

    private func removePendingCleanupRecord(for identifier: UUID) {
        guard cleanupRegistryIsUsable, pendingCleanupRecords[identifier] != nil else {
            return
        }
        var updatedRecords = pendingCleanupRecords
        updatedRecords.removeValue(forKey: identifier)
        do {
            try cleanupRegistry.save(Array(updatedRecords.values))
            pendingCleanupRecords = updatedRecords
        } catch {
            NSLog("MyMacFinder could not remove completed archive preview cleanup record: %@", error.localizedDescription)
        }
    }

    private func saveExternalOpenRecords() {
        do {
            try saveExternalOpenRecords(externalOpenRecords)
        } catch {
            NSLog("MyMacFinder could not save retained archive preview artifacts: %@", error.localizedDescription)
        }
    }

    private func saveExternalOpenRecords(_ records: [UUID: ExternalOpenRecord]) throws {
        guard retentionRegistryIsUsable else {
            return
        }
        try retentionRegistry.save(
            records.values.map {
                RetainedArchiveTemporaryArtifact($0.artifact, openedAt: $0.openedAt)
            }
        )
    }
}
