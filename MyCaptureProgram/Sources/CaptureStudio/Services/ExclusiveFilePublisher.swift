import Darwin
import Foundation

enum ExclusiveFilePublisher {
    static func publish(
        from sourceURL: URL,
        to destinationURL: URL,
        expectedSourceIdentity: CaptureFileIdentity? = nil,
        sourceIdentityWasCheckedBeforeRemoval: (() throws -> Void)? = nil,
        quarantinedSourceWillBeRemoved: (() throws -> Void)? = nil,
        destinationWasPublished: (() throws -> Void)? = nil
    ) throws {
        let sourceIdentity = try expectedSourceIdentity ?? CaptureFileIdentity.existingFile(at: sourceURL)
        guard sourceIdentity.matchesExistingFile(at: sourceURL) else {
            throw FileOutputError.sourceFileChanged
        }

        let linkResult = withFileSystemPaths(sourceURL, destinationURL) { sourcePath, destinationPath in
            Darwin.link(sourcePath, destinationPath)
        }
        if linkResult == 0 {
            do {
                try destinationWasPublished?()
            } catch {
                removeIfStillOwned(destinationURL, identity: sourceIdentity)
                throw error
            }
            let destinationIdentity = try CaptureFileIdentity.existingFile(at: destinationURL)
            guard destinationIdentity == sourceIdentity else {
                throw FileOutputError.sourceFileChanged
            }
            _ = try? removeFileIfStillOwned(
                sourceURL,
                identity: sourceIdentity,
                identityWasChecked: sourceIdentityWasCheckedBeforeRemoval,
                quarantinedFileWillBeRemoved: quarantinedSourceWillBeRemoved
            )
            return
        }

        let linkError = errno
        guard sourceIdentity.matchesExistingFile(at: sourceURL) else {
            throw FileOutputError.sourceFileChanged
        }
        guard canFallback(after: linkError) else {
            throw posixError(linkError)
        }
        try copyExclusively(
            from: sourceURL,
            to: destinationURL,
            expectedSourceIdentity: sourceIdentity,
            sourceIdentityWasCheckedBeforeRemoval: sourceIdentityWasCheckedBeforeRemoval,
            quarantinedSourceWillBeRemoved: quarantinedSourceWillBeRemoved,
            destinationWasPublished: destinationWasPublished
        )
    }

    static func copyExclusively(
        from sourceURL: URL,
        to destinationURL: URL,
        expectedSourceIdentity: CaptureFileIdentity? = nil,
        copyDidWriteChunk: (() -> Void)? = nil,
        sourceIdentityWasCheckedBeforeRemoval: (() throws -> Void)? = nil,
        quarantinedSourceWillBeRemoved: (() throws -> Void)? = nil,
        destinationWasPublished: (() throws -> Void)? = nil
    ) throws {
        let sourceDescriptor = sourceURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC)
        }
        guard sourceDescriptor >= 0 else {
            throw posixError(errno)
        }
        defer { Darwin.close(sourceDescriptor) }

        var sourceInformation = stat()
        guard Darwin.fstat(sourceDescriptor, &sourceInformation) == 0 else {
            throw posixError(errno)
        }
        let sourceIdentity = CaptureFileIdentity(
            device: UInt64(sourceInformation.st_dev),
            inode: UInt64(sourceInformation.st_ino)
        )
        if let expectedSourceIdentity, sourceIdentity != expectedSourceIdentity {
            throw FileOutputError.sourceFileChanged
        }

        let temporaryURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".CaptureStudio-Publish-\(UUID().uuidString).tmp")
        let destinationDescriptor = temporaryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            let permissions = mode_t(sourceInformation.st_mode & 0o777)
            return Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, permissions)
        }
        guard destinationDescriptor >= 0 else {
            throw posixError(errno)
        }

        var destinationInformation = stat()
        guard Darwin.fstat(destinationDescriptor, &destinationInformation) == 0 else {
            let openError = errno
            Darwin.close(destinationDescriptor)
            throw posixError(openError)
        }
        let destinationIdentity = CaptureFileIdentity(
            device: UInt64(destinationInformation.st_dev),
            inode: UInt64(destinationInformation.st_ino)
        )
        var temporaryFileExists = true
        var publishedDestinationIdentity: CaptureFileIdentity?
        var shouldRollbackDestination = false
        defer {
            if temporaryFileExists {
                removeIfStillOwned(temporaryURL, identity: destinationIdentity)
            }
            if shouldRollbackDestination, let publishedDestinationIdentity {
                removeIfStillOwned(destinationURL, identity: publishedDestinationIdentity)
            }
        }

        do {
            defer { Darwin.close(destinationDescriptor) }
            var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
            while true {
                let readCount = buffer.withUnsafeMutableBytes { rawBuffer in
                    Darwin.read(sourceDescriptor, rawBuffer.baseAddress, rawBuffer.count)
                }
                if readCount == 0 {
                    break
                }
                if readCount < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw posixError(errno)
                }

                var writtenCount = 0
                while writtenCount < readCount {
                    let writeCount = buffer.withUnsafeBytes { rawBuffer in
                        Darwin.write(
                            destinationDescriptor,
                            rawBuffer.baseAddress?.advanced(by: writtenCount),
                            readCount - writtenCount
                        )
                    }
                    if writeCount < 0 {
                        if errno == EINTR {
                            continue
                        }
                        throw posixError(errno)
                    }
                    writtenCount += writeCount
                }
                copyDidWriteChunk?()
            }

            guard Darwin.fsync(destinationDescriptor) == 0 else {
                throw posixError(errno)
            }
        } catch {
            throw error
        }

        let linkResult = withFileSystemPaths(temporaryURL, destinationURL) { temporaryPath, destinationPath in
            Darwin.link(temporaryPath, destinationPath)
        }
        guard linkResult == 0 else {
            throw posixError(errno)
        }
        publishedDestinationIdentity = destinationIdentity
        shouldRollbackDestination = true
        try destinationWasPublished?()
        let finalIdentity = try CaptureFileIdentity.existingFile(at: destinationURL)
        guard finalIdentity == destinationIdentity else {
            throw FileOutputError.sourceFileChanged
        }
        synchronizeDirectory(containing: destinationURL)

        guard try removeFileIfStillOwned(temporaryURL, identity: destinationIdentity) else {
            throw FileOutputError.sourceFileChanged
        }
        temporaryFileExists = false

        shouldRollbackDestination = false
        _ = try? removeFileIfStillOwned(
            sourceURL,
            identity: sourceIdentity,
            identityWasChecked: sourceIdentityWasCheckedBeforeRemoval,
            quarantinedFileWillBeRemoved: quarantinedSourceWillBeRemoved
        )
    }

    private static func canFallback(after error: Int32) -> Bool {
        error == EXDEV
            || error == ENOTSUP
            || error == EOPNOTSUPP
            || error == EINVAL
            || error == ENOSYS
            || error == EPERM
            || error == EMLINK
    }

    @discardableResult
    static func discardFileIfStillOwned(
        _ url: URL,
        identity: CaptureFileIdentity
    ) throws -> Bool {
        try removeFileIfStillOwned(url, identity: identity)
    }

    @discardableResult
    private static func removeFileIfStillOwned(
        _ url: URL,
        identity: CaptureFileIdentity,
        identityWasChecked: (() throws -> Void)? = nil,
        quarantinedFileWillBeRemoved: (() throws -> Void)? = nil
    ) throws -> Bool {
        guard identity.matchesExistingFile(at: url) else {
            return false
        }
        try identityWasChecked?()

        let quarantineDirectoryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".CaptureStudio-Remove-\(UUID().uuidString)", isDirectory: true)
        let createResult = quarantineDirectoryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.mkdir(path, S_IRWXU)
        }
        guard createResult == 0 else {
            throw posixError(errno)
        }
        let quarantineDirectoryIdentity = try CaptureFileIdentity.existingFile(at: quarantineDirectoryURL)
        defer {
            removeDirectoryIfStillOwned(
                quarantineDirectoryURL,
                identity: quarantineDirectoryIdentity
            )
        }

        let quarantinedURL = quarantineDirectoryURL.appendingPathComponent("owned")
        let moveResult = withFileSystemPaths(url, quarantinedURL) { sourcePath, quarantinePath in
            Darwin.renamex_np(sourcePath, quarantinePath, UInt32(RENAME_EXCL))
        }
        guard moveResult == 0 else {
            if errno == ENOENT {
                return false
            }
            throw posixError(errno)
        }

        do {
            let quarantinedIdentity = try CaptureFileIdentity.existingFile(at: quarantinedURL)
            guard quarantinedIdentity == identity else {
                guard restoreQuarantinedFile(from: quarantinedURL, to: url) else {
                    throw FileOutputError.sourceFileChanged
                }
                return false
            }
            try quarantinedFileWillBeRemoved?()

            let result = quarantinedURL.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else {
                    errno = EINVAL
                    return -1
                }
                return Darwin.unlink(path)
            }
            guard result == 0 else {
                throw posixError(errno)
            }
            return true
        } catch {
            _ = restoreQuarantinedFile(from: quarantinedURL, to: url)
            throw error
        }
    }

    private static func restoreQuarantinedFile(from quarantinedURL: URL, to originalURL: URL) -> Bool {
        withFileSystemPaths(quarantinedURL, originalURL) { quarantinePath, sourcePath in
            Darwin.renamex_np(quarantinePath, sourcePath, UInt32(RENAME_EXCL))
        } == 0
    }

    private static func removeIfStillOwned(_ url: URL, identity: CaptureFileIdentity) {
        _ = try? removeFileIfStillOwned(url, identity: identity)
    }

    private static func removeDirectoryIfStillOwned(_ url: URL, identity: CaptureFileIdentity) {
        guard identity.matchesExistingFile(at: url) else {
            return
        }
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return
            }
            _ = Darwin.rmdir(path)
        }
    }

    private static func synchronizeDirectory(containing url: URL) {
        let directoryURL = url.deletingLastPathComponent()
        let descriptor = directoryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            return
        }
        _ = Darwin.fsync(descriptor)
        Darwin.close(descriptor)
    }

    private static func withFileSystemPaths(
        _ sourceURL: URL,
        _ destinationURL: URL,
        operation: (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
    ) -> Int32 {
        sourceURL.withUnsafeFileSystemRepresentation { sourcePath in
            guard let sourcePath else {
                errno = EINVAL
                return -1
            }
            return destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                guard let destinationPath else {
                    errno = EINVAL
                    return -1
                }
                return operation(sourcePath, destinationPath)
            }
        }
    }

    private static func posixError(_ value: Int32) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: value) ?? .EIO)
    }
}

final class SecureTemporaryOutputWorkspace: @unchecked Sendable {
    let directoryURL: URL
    let outputURL: URL

    private let directoryIdentity: CaptureFileIdentity

    init(
        fileExtension: String,
        baseDirectory: URL = FileManager.default.temporaryDirectory
    ) throws {
        let safeExtension = fileExtension.allSatisfy { $0.isLetter || $0.isNumber }
            ? fileExtension
            : "tmp"

        var createdDirectoryURL: URL?
        for _ in 0..<100 {
            let candidate = baseDirectory.appendingPathComponent(
                ".CaptureStudio-output-\(UUID().uuidString)",
                isDirectory: true
            )
            let result = candidate.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else {
                    errno = EINVAL
                    return -1
                }
                return Darwin.mkdir(path, S_IRWXU)
            }
            if result == 0 {
                createdDirectoryURL = candidate
                break
            }
            guard errno == EEXIST else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }

        guard let createdDirectoryURL else {
            throw FileOutputError.unableToAllocateFilename
        }
        directoryURL = createdDirectoryURL
        outputURL = createdDirectoryURL
            .appendingPathComponent("output")
            .appendingPathExtension(safeExtension)
        directoryIdentity = try CaptureFileIdentity.existingFile(at: createdDirectoryURL)
    }

    deinit {
        cleanup()
    }

    func publish(to destinationURL: URL) throws {
        guard directoryIdentity.matchesExistingFile(at: directoryURL) else {
            throw POSIXError(.EIO)
        }
        try ExclusiveFilePublisher.publish(from: outputURL, to: destinationURL)
        removeDirectoryIfEmpty()
    }

    func cleanup() {
        guard directoryIdentity.matchesExistingFile(at: directoryURL) else {
            return
        }
        outputURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return
            }
            _ = Darwin.unlink(path)
        }
        removeDirectoryIfEmpty()
    }

    private func removeDirectoryIfEmpty() {
        guard directoryIdentity.matchesExistingFile(at: directoryURL) else {
            return
        }
        directoryURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return
            }
            _ = Darwin.rmdir(path)
        }
    }
}
