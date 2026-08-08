import Darwin
import Foundation

struct ArchiveTemporaryFileSystemHooks: @unchecked Sendable {
    var afterReleaseValidation: (@Sendable (URL) throws -> Void)?
    var afterOwnerQuarantine: (@Sendable (URL) throws -> Void)?
    var beforeQuarantineRestore: (@Sendable (URL) throws -> Void)?
    var beforeOutputOwnerOpen: (@Sendable (TemporaryArchiveArtifact) throws -> Void)?
    var beforeOutputLeafOpen: (@Sendable (TemporaryArchiveArtifact) throws -> Void)?
    var afterOutputEnumeration: (@Sendable (URL) throws -> Void)?
    var afterOutputQuarantine: (@Sendable (URL) throws -> Void)?
    var beforeOwnerUnlink: (@Sendable (URL) throws -> Void)?
    var afterPublishedOutputOwnerOpen: (@Sendable (TemporaryArchiveArtifact) throws -> Void)?
    var afterDirectoryDescriptorDuplicate: (@Sendable (Int32) throws -> Void)?
    var beforeDirectoryEntryRead: (@Sendable () throws -> Void)?
    var closeDirectoryStream: (@Sendable (UnsafeMutablePointer<DIR>) -> Int32)?

    static let none = ArchiveTemporaryFileSystemHooks()
}

final class ArchiveTemporaryOutputFile: @unchecked Sendable {
    let identity: FileSystemPathIdentity.FileSystemEntryIdentity

    private let path: String
    private var descriptor: Int32

    init(descriptor: Int32, path: String, identity: FileSystemPathIdentity.FileSystemEntryIdentity) {
        self.descriptor = descriptor
        self.path = path
        self.identity = identity
    }

    deinit {
        if descriptor >= 0 {
            ArchiveTemporaryFileSystem.closeIgnoringError(descriptor)
        }
    }

    func write(_ data: Data) throws {
        guard descriptor >= 0 else {
            throw ExplorerError.operationFailed("Archive preview output is already closed: \(path)")
        }
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            var offset = 0
            while offset < rawBuffer.count {
                let result = Darwin.write(descriptor, baseAddress.advanced(by: offset), rawBuffer.count - offset)
                if result > 0 {
                    offset += result
                } else if result == -1, errno == EINTR {
                    continue
                } else if result == 0 {
                    throw ExplorerError.operationFailed("Archive preview output write made no progress: \(path)")
                } else {
                    throw ArchiveTemporaryFileSystem.posixError("write archive preview output", path: path)
                }
            }
        }
    }

    func close() throws {
        guard descriptor >= 0 else {
            return
        }
        let descriptorToClose = descriptor
        descriptor = -1
        try ArchiveTemporaryFileSystem.close(descriptorToClose, path: path)
    }
}

struct ArchiveTemporaryFileSystem: @unchecked Sendable {
    private let fileManager: FileManager
    private let hooks: ArchiveTemporaryFileSystemHooks

    init(fileManager: FileManager, hooks: ArchiveTemporaryFileSystemHooks = .none) {
        self.fileManager = fileManager
        self.hooks = hooks
    }

    func allocate(
        extractionRoot: URL,
        identifier: UUID,
        leafName: String
    ) throws -> TemporaryArchiveArtifact {
        try fileManager.createDirectory(
            at: extractionRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let rootDescriptor = try openDirectory(atPath: extractionRoot.path)
        defer { Self.closeIgnoringError(rootDescriptor) }
        try setPermissions(rootDescriptor, mode: 0o700, path: extractionRoot.path)

        let ownerName = identifier.uuidString
        try mkdir(at: rootDescriptor, name: ownerName, mode: 0o700, path: extractionRoot.path)
        let ownerURL = extractionRoot.appendingPathComponent(ownerName, isDirectory: true).standardizedFileURL

        do {
            let ownerDescriptor = try openDirectory(at: rootDescriptor, name: ownerName, path: ownerURL.path)
            defer { Self.closeIgnoringError(ownerDescriptor) }
            try setPermissions(ownerDescriptor, mode: 0o700, path: ownerURL.path)
            let identity = try descriptorIdentity(ownerDescriptor, path: ownerURL.path)
            guard FileSystemPathIdentity.isDirectory(identity) else {
                throw ExplorerError.operationFailed("Archive preview artifact owner is not a directory: \(ownerURL.path)")
            }
            return TemporaryArchiveArtifact(
                url: ownerURL.appendingPathComponent(leafName).standardizedFileURL,
                ownerDirectoryURL: ownerURL,
                ownerIdentifier: identifier,
                expectedOwnerIdentity: identity
            )
        } catch let allocationError {
            do {
                try unlink(
                    at: rootDescriptor,
                    name: ownerName,
                    isDirectory: true,
                    path: ownerURL.path
                )
            } catch let cleanupError {
                throw ExplorerError.operationFailed(
                    "Archive preview allocation failed (\(allocationError.localizedDescription)) and owner cleanup "
                        + "also failed at \(ownerURL.path): \(cleanupError.localizedDescription)"
                )
            }
            throw allocationError
        }
    }

    func openOutputFile(
        extractionRoot: URL,
        artifact: TemporaryArchiveArtifact
    ) throws -> ArchiveTemporaryOutputFile {
        try validateStructure(extractionRoot: extractionRoot, artifact: artifact)
        let rootDescriptor = try openDirectory(atPath: extractionRoot.path)
        defer { Self.closeIgnoringError(rootDescriptor) }

        try hooks.beforeOutputOwnerOpen?(artifact)
        let ownerDescriptor = try openDirectory(
            at: rootDescriptor,
            name: artifact.ownerIdentifier.uuidString,
            path: artifact.ownerDirectoryURL.path
        )
        defer { Self.closeIgnoringError(ownerDescriptor) }

        let ownerIdentity = try descriptorIdentity(ownerDescriptor, path: artifact.ownerDirectoryURL.path)
        guard ownerIdentity == artifact.expectedOwnerIdentity else {
            throw ExplorerError.operationFailed(
                "Archive preview artifact owner identity changed: \(artifact.ownerDirectoryURL.path)"
            )
        }

        try hooks.beforeOutputLeafOpen?(artifact)
        let leafName = artifact.url.lastPathComponent
        let outputDescriptor = try openOutput(at: ownerDescriptor, name: leafName, path: artifact.url.path)
        do {
            try setPermissions(outputDescriptor, mode: 0o600, path: artifact.url.path)
            let outputIdentity = try descriptorIdentity(outputDescriptor, path: artifact.url.path)
            return ArchiveTemporaryOutputFile(
                descriptor: outputDescriptor,
                path: artifact.url.path,
                identity: outputIdentity
            )
        } catch {
            Self.closeIgnoringError(outputDescriptor)
            throw error
        }
    }

    func validatePublishedOutput(
        extractionRoot: URL,
        artifact: TemporaryArchiveArtifact
    ) throws {
        guard let outputIdentity = artifact.expectedOutputIdentity else {
            throw ExplorerError.operationFailed(
                "Archive preview output identity is unavailable before publication: \(artifact.url.path)"
            )
        }
        try validateStructure(extractionRoot: extractionRoot, artifact: artifact)
        let rootDescriptor = try openDirectory(atPath: extractionRoot.path)
        defer { Self.closeIgnoringError(rootDescriptor) }
        let ownerDescriptor = try openDirectory(
            at: rootDescriptor,
            name: artifact.ownerIdentifier.uuidString,
            path: artifact.ownerDirectoryURL.path
        )
        defer { Self.closeIgnoringError(ownerDescriptor) }

        try hooks.afterPublishedOutputOwnerOpen?(artifact)
        guard try descriptorIdentity(ownerDescriptor, path: artifact.ownerDirectoryURL.path)
            == artifact.expectedOwnerIdentity else {
            throw ExplorerError.operationFailed(
                "Archive preview artifact owner identity changed before publication: \(artifact.ownerDirectoryURL.path)"
            )
        }
        guard try entryIdentity(
            at: ownerDescriptor,
            name: artifact.url.lastPathComponent,
            path: artifact.url.path
        ) == outputIdentity else {
            throw ExplorerError.operationFailed(
                "Archive preview output identity changed before publication: \(artifact.url.path)"
            )
        }
        guard try entryIdentity(
            at: rootDescriptor,
            name: artifact.ownerIdentifier.uuidString,
            path: artifact.ownerDirectoryURL.path
        ) == artifact.expectedOwnerIdentity else {
            throw ExplorerError.operationFailed(
                "Archive preview artifact owner identity changed before publication: \(artifact.ownerDirectoryURL.path)"
            )
        }
    }

    func validateOwnership(extractionRoot: URL, artifact: TemporaryArchiveArtifact) throws {
        try validateStructure(extractionRoot: extractionRoot, artifact: artifact)
        let rootDescriptor = try openDirectory(atPath: extractionRoot.path)
        defer { Self.closeIgnoringError(rootDescriptor) }
        let identity = try entryIdentity(
            at: rootDescriptor,
            name: artifact.ownerIdentifier.uuidString,
            path: artifact.ownerDirectoryURL.path
        )
        guard FileSystemPathIdentity.isDirectory(identity) else {
            throw ExplorerError.operationFailed(
                "Archive preview artifact owner is not a directory: \(artifact.ownerDirectoryURL.path)"
            )
        }
        guard identity == artifact.expectedOwnerIdentity else {
            throw ExplorerError.operationFailed(
                "Archive preview artifact owner identity changed: \(artifact.ownerDirectoryURL.path)"
            )
        }
    }

    func removeOwner(extractionRoot: URL, artifact: TemporaryArchiveArtifact) throws {
        try validateStructure(extractionRoot: extractionRoot, artifact: artifact)
        let rootDescriptor = try openDirectory(atPath: extractionRoot.path)
        defer { Self.closeIgnoringError(rootDescriptor) }

        let ownerName = artifact.ownerIdentifier.uuidString
        let initialIdentity = try entryIdentity(
            at: rootDescriptor,
            name: ownerName,
            path: artifact.ownerDirectoryURL.path
        )
        guard FileSystemPathIdentity.isDirectory(initialIdentity) else {
            throw ExplorerError.operationFailed(
                "Archive preview artifact owner is not a directory: \(artifact.ownerDirectoryURL.path)"
            )
        }
        guard initialIdentity == artifact.expectedOwnerIdentity else {
            throw ExplorerError.operationFailed(
                "Archive preview artifact owner identity changed: \(artifact.ownerDirectoryURL.path)"
            )
        }

        try hooks.afterReleaseValidation?(artifact.ownerDirectoryURL)

        let quarantineName = ".MyMacFinderArchivePreview-\(UUID().uuidString)"
        let quarantineURL = extractionRoot.appendingPathComponent(quarantineName, isDirectory: true)
        try rename(
            fromDescriptor: rootDescriptor,
            from: ownerName,
            toDescriptor: rootDescriptor,
            to: quarantineName,
            path: artifact.ownerDirectoryURL.path
        )

        do {
            try hooks.afterOwnerQuarantine?(quarantineURL)
            let quarantinedIdentity = try entryIdentity(
                at: rootDescriptor,
                name: quarantineName,
                path: quarantineURL.path
            )
            guard quarantinedIdentity == artifact.expectedOwnerIdentity else {
                try restoreChangedQuarantine(
                    rootDescriptor: rootDescriptor,
                    ownerName: ownerName,
                    quarantineName: quarantineName,
                    quarantineURL: quarantineURL,
                    artifact: artifact
                )
            }

            let ownerDescriptor = try openDirectory(
                at: rootDescriptor,
                name: quarantineName,
                path: quarantineURL.path
            )
            defer { Self.closeIgnoringError(ownerDescriptor) }
            guard try descriptorIdentity(ownerDescriptor, path: quarantineURL.path)
                == artifact.expectedOwnerIdentity else {
                try restoreChangedQuarantine(
                    rootDescriptor: rootDescriptor,
                    ownerName: ownerName,
                    quarantineName: quarantineName,
                    quarantineURL: quarantineURL,
                    artifact: artifact
                )
            }

            try removeExpectedOutput(
                descriptor: ownerDescriptor,
                path: quarantineURL.path,
                artifact: artifact
            )
            try hooks.beforeOwnerUnlink?(quarantineURL)
            guard try entryIdentity(
                at: rootDescriptor,
                name: quarantineName,
                path: quarantineURL.path
            ) == artifact.expectedOwnerIdentity else {
                throw ExplorerError.operationFailed(
                    "Archive preview quarantine identity changed; unrelated content was preserved at \(quarantineURL.path)"
                )
            }
            try unlink(at: rootDescriptor, name: quarantineName, isDirectory: true, path: quarantineURL.path)
        } catch {
            try restoreExpectedQuarantineIfPossible(
                rootDescriptor: rootDescriptor,
                ownerName: ownerName,
                quarantineName: quarantineName,
                quarantineURL: quarantineURL,
                artifact: artifact,
                originalError: error
            )
        }
    }

    private func restoreChangedQuarantine(
        rootDescriptor: Int32,
        ownerName: String,
        quarantineName: String,
        quarantineURL: URL,
        artifact: TemporaryArchiveArtifact
    ) throws -> Never {
        if entryIdentityIfPresent(at: rootDescriptor, name: ownerName) == nil {
            try hooks.beforeQuarantineRestore?(artifact.ownerDirectoryURL)
            do {
                try rename(
                    fromDescriptor: rootDescriptor,
                    from: quarantineName,
                    toDescriptor: rootDescriptor,
                    to: ownerName,
                    path: quarantineURL.path
                )
            } catch {
                throw ExplorerError.operationFailed(
                    "Archive preview artifact owner identity changed; unrelated content was preserved at "
                        + "\(quarantineURL.path), and restore failed: \(error.localizedDescription)"
                )
            }
            throw ExplorerError.operationFailed(
                "Archive preview artifact owner identity changed; unrelated content was restored at "
                    + artifact.ownerDirectoryURL.path
            )
        }
        throw ExplorerError.operationFailed(
            "Archive preview artifact owner identity changed; unrelated content was preserved at \(quarantineURL.path)"
        )
    }

    private func restoreExpectedQuarantineIfPossible(
        rootDescriptor: Int32,
        ownerName: String,
        quarantineName: String,
        quarantineURL: URL,
        artifact: TemporaryArchiveArtifact,
        originalError: Error
    ) throws -> Never {
        let quarantineIdentity = entryIdentityIfPresent(at: rootDescriptor, name: quarantineName)
        if quarantineIdentity == artifact.expectedOwnerIdentity {
            guard entryIdentityIfPresent(at: rootDescriptor, name: ownerName) == nil else {
                throw ExplorerError.operationFailed(
                    "\(originalError.localizedDescription) The recorded owner was preserved at "
                        + "\(quarantineURL.path) because the original path is occupied."
                )
            }
            try hooks.beforeQuarantineRestore?(artifact.ownerDirectoryURL)
            do {
                try rename(
                    fromDescriptor: rootDescriptor,
                    from: quarantineName,
                    toDescriptor: rootDescriptor,
                    to: ownerName,
                    path: artifact.ownerDirectoryURL.path
                )
            } catch {
                throw ExplorerError.operationFailed(
                    "\(originalError.localizedDescription) The recorded owner was preserved at "
                        + "\(quarantineURL.path); restore failed: "
                        + error.localizedDescription
                )
            }
            throw rebasedCleanupError(
                originalError,
                quarantinedRootPath: quarantineURL.path,
                restoredRootPath: artifact.ownerDirectoryURL.path
            )
        }
        throw originalError
    }

    private func removeExpectedOutput(
        descriptor: Int32,
        path: String,
        artifact: TemporaryArchiveArtifact
    ) throws {
        let names = try directoryEntryNames(descriptor: descriptor, path: path)
        let outputName = artifact.url.lastPathComponent

        guard !names.isEmpty else {
            return
        }

        guard let outputIdentity = artifact.expectedOutputIdentity else {
            throw preservedEntryError(
                "Archive preview owner contains an unexpected entry",
                relativePath: names.sorted()[0]
            )
        }

        guard names.count == 1, names[0] == outputName else {
            let unexpectedName = names.first(where: { $0 != outputName }) ?? outputName
            throw preservedEntryError(
                "Archive preview owner does not contain only its expected output",
                relativePath: unexpectedName
            )
        }

        let outputPath = (path as NSString).appendingPathComponent(outputName)
        try hooks.afterOutputEnumeration?(URL(fileURLWithPath: outputPath))
        guard try entryIdentity(at: descriptor, name: outputName, path: outputPath) == outputIdentity else {
            throw preservedEntryError(
                "Archive preview output identity changed",
                relativePath: outputName
            )
        }

        let quarantineName = ".MyMacFinderEntry-\(UUID().uuidString)"
        try rename(
            fromDescriptor: descriptor,
            from: outputName,
            toDescriptor: descriptor,
            to: quarantineName,
            path: outputPath
        )
        let quarantinePath = (path as NSString).appendingPathComponent(quarantineName)
        try hooks.afterOutputQuarantine?(URL(fileURLWithPath: quarantinePath))
        guard try entryIdentity(at: descriptor, name: quarantineName, path: quarantinePath) == outputIdentity else {
            throw preservedEntryError(
                "Archive preview output identity changed after quarantine",
                relativePath: quarantineName
            )
        }
        try unlink(at: descriptor, name: quarantineName, isDirectory: false, path: quarantinePath)

        let remainingNames = try directoryEntryNames(descriptor: descriptor, path: path)
        guard remainingNames.isEmpty else {
            let remainingName = remainingNames.sorted()[0]
            throw preservedEntryError(
                "Archive preview owner changed before removal",
                relativePath: remainingName
            )
        }
    }

    private func preservedEntryError(_ reason: String, relativePath: String) -> PreservedArchiveEntryError {
        PreservedArchiveEntryError(reason: reason, relativePath: relativePath)
    }

    private func rebasedCleanupError(
        _ error: Error,
        quarantinedRootPath: String,
        restoredRootPath: String
    ) -> Error {
        if let preservedError = error as? PreservedArchiveEntryError {
            return ExplorerError.operationFailed(preservedError.description(rootPath: restoredRootPath))
        }
        guard case ExplorerError.operationFailed(let message) = error,
              message.contains(quarantinedRootPath) else {
            return error
        }
        return ExplorerError.operationFailed(
            message.replacingOccurrences(of: quarantinedRootPath, with: restoredRootPath)
        )
    }

    private func directoryEntryNames(descriptor: Int32, path: String) throws -> [String] {
        let duplicate = try retryingInt32("duplicate archive preview directory", path: path) {
            Darwin.fcntl(descriptor, F_DUPFD_CLOEXEC, 0)
        }
        do {
            try hooks.afterDirectoryDescriptorDuplicate?(duplicate)
        } catch {
            Self.closeIgnoringError(duplicate)
            throw error
        }
        guard let directory = fdopendir(duplicate) else {
            Self.closeIgnoringError(duplicate)
            throw Self.posixError("enumerate archive preview directory", path: path)
        }

        var names: [String] = []
        var enumerationError: Error?
        while true {
            do {
                try hooks.beforeDirectoryEntryRead?()
            } catch {
                enumerationError = error
                break
            }
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 {
                    enumerationError = Self.posixError(
                        "enumerate archive preview directory",
                        path: path,
                        code: errno
                    )
                }
                break
            }
            let name = withUnsafeBytes(of: entry.pointee.d_name) { bytes in
                String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            if name != ".", name != ".." {
                names.append(name)
            }
        }

        let closeResult = hooks.closeDirectoryStream?(directory) ?? Darwin.closedir(directory)
        if closeResult != 0, enumerationError == nil {
            enumerationError = Self.posixError(
                "close archive preview directory stream",
                path: path,
                code: errno
            )
        }
        if let enumerationError {
            throw enumerationError
        }
        return names
    }

    private func validateStructure(extractionRoot: URL, artifact: TemporaryArchiveArtifact) throws {
        let ownerDirectoryURL = artifact.ownerDirectoryURL.standardizedFileURL
        guard ownerDirectoryURL.lastPathComponent == artifact.ownerIdentifier.uuidString else {
            throw ExplorerError.operationFailed(
                "Archive preview artifact owner does not match its identifier: \(ownerDirectoryURL.path)"
            )
        }
        guard ownerDirectoryURL.deletingLastPathComponent().standardizedFileURL.path == extractionRoot.path,
              FileSystemPathIdentity.canonicalDirectory(ownerDirectoryURL.deletingLastPathComponent()).path
                == extractionRoot.path,
              artifact.url.standardizedFileURL.deletingLastPathComponent().path == ownerDirectoryURL.path,
              artifact.url.lastPathComponent != ".",
              artifact.url.lastPathComponent != "..",
              !artifact.url.lastPathComponent.contains("/") else {
            throw ExplorerError.operationFailed(
                "Archive preview artifact is not an immediate child of its extraction root: \(ownerDirectoryURL.path)"
            )
        }
    }

    private func openDirectory(atPath path: String) throws -> Int32 {
        try retryingInt32("open archive preview directory", path: path) {
            path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        }
    }

    private func openDirectory(at descriptor: Int32, name: String, path: String) throws -> Int32 {
        try retryingInt32("open archive preview directory", path: path) {
            name.withCString { Darwin.openat(descriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        }
    }

    private func openOutput(at descriptor: Int32, name: String, path: String) throws -> Int32 {
        try retryingInt32("create archive preview output", path: path) {
            name.withCString {
                Darwin.openat(
                    descriptor,
                    $0,
                    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                    mode_t(0o600)
                )
            }
        }
    }

    private func mkdir(at descriptor: Int32, name: String, mode: mode_t, path: String) throws {
        while true {
            let result = name.withCString { Darwin.mkdirat(descriptor, $0, mode) }
            if result == 0 { return }
            if errno == EINTR { continue }
            throw Self.posixError("create archive preview owner", path: path + "/" + name)
        }
    }

    private func rename(
        fromDescriptor: Int32,
        from: String,
        toDescriptor: Int32,
        to: String,
        path: String
    ) throws {
        while true {
            let result = from.withCString { fromName in
                to.withCString { toName in
                    Darwin.renameatx_np(
                        fromDescriptor,
                        fromName,
                        toDescriptor,
                        toName,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            if result == 0 { return }
            if errno == EINTR { continue }
            throw Self.posixError("quarantine archive preview entry", path: path)
        }
    }

    private func setPermissions(_ descriptor: Int32, mode: mode_t, path: String) throws {
        while true {
            if Darwin.fchmod(descriptor, mode) == 0 { return }
            if errno == EINTR { continue }
            throw Self.posixError("set archive preview permissions", path: path)
        }
    }

    private func unlink(at descriptor: Int32, name: String, isDirectory: Bool, path: String) throws {
        let flags = isDirectory ? AT_REMOVEDIR : 0
        while true {
            let result = name.withCString { Darwin.unlinkat(descriptor, $0, flags) }
            if result == 0 { return }
            if errno == EINTR { continue }
            throw Self.posixError("remove archive preview entry", path: path)
        }
    }

    private func entryIdentity(
        at descriptor: Int32,
        name: String,
        path: String
    ) throws -> FileSystemPathIdentity.FileSystemEntryIdentity {
        var info = stat()
        while true {
            let result = name.withCString { Darwin.fstatat(descriptor, $0, &info, AT_SYMLINK_NOFOLLOW) }
            if result == 0 { return identity(from: info) }
            if errno == EINTR { continue }
            throw Self.posixError("inspect archive preview entry", path: path)
        }
    }

    private func entryIdentityIfPresent(at descriptor: Int32, name: String)
        -> FileSystemPathIdentity.FileSystemEntryIdentity? {
        var info = stat()
        while true {
            let result = name.withCString { Darwin.fstatat(descriptor, $0, &info, AT_SYMLINK_NOFOLLOW) }
            if result == 0 { return identity(from: info) }
            if errno == EINTR { continue }
            return nil
        }
    }

    private func descriptorIdentity(
        _ descriptor: Int32,
        path: String
    ) throws -> FileSystemPathIdentity.FileSystemEntryIdentity {
        var info = stat()
        while true {
            if Darwin.fstat(descriptor, &info) == 0 { return identity(from: info) }
            if errno == EINTR { continue }
            throw Self.posixError("inspect archive preview descriptor", path: path)
        }
    }

    private func identity(from info: stat) -> FileSystemPathIdentity.FileSystemEntryIdentity {
        FileSystemPathIdentity.FileSystemEntryIdentity(
            device: UInt64(bitPattern: Int64(info.st_dev)),
            inode: UInt64(info.st_ino),
            generation: UInt32(info.st_gen),
            mode: UInt32(info.st_mode)
        )
    }

    private func retryingInt32(
        _ operation: String,
        path: String,
        body: () -> Int32
    ) throws -> Int32 {
        while true {
            let result = body()
            if result >= 0 { return result }
            if errno == EINTR { continue }
            throw Self.posixError(operation, path: path)
        }
    }

    static func close(_ descriptor: Int32, path: String) throws {
        while true {
            if Darwin.close(descriptor) == 0 { return }
            if errno == EINTR { continue }
            throw posixError("close archive preview descriptor", path: path)
        }
    }

    static func closeIgnoringError(_ descriptor: Int32) {
        while Darwin.close(descriptor) == -1, errno == EINTR {}
    }

    static func posixError(_ operation: String, path: String) -> ExplorerError {
        posixError(operation, path: path, code: errno)
    }

    static func posixError(_ operation: String, path: String, code: Int32) -> ExplorerError {
        return .operationFailed(
            "Could not \(operation) at \(path): \(String(cString: strerror(code))) (errno \(code))."
        )
    }
}

private struct PreservedArchiveEntryError: LocalizedError {
    let reason: String
    let relativePath: String

    var errorDescription: String? {
        description(rootPath: "")
    }

    func description(rootPath: String) -> String {
        let path = rootPath.isEmpty
            ? relativePath
            : (rootPath as NSString).appendingPathComponent(relativePath)
        return "\(reason); content was preserved at \(path)"
    }
}
