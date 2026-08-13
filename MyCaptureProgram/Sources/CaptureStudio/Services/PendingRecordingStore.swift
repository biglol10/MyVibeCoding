import Darwin
import Foundation

public struct PendingRecording: Equatable, Sendable {
    public let fileURL: URL
    public let createdAt: Date
    public let fileIdentity: CaptureFileIdentity
}

public enum PendingRecordingStoreError: LocalizedError, Equatable {
    case unsafeDirectory
    case directoryChanged

    public var errorDescription: String? {
        switch self {
        case .unsafeDirectory:
            return "The recording recovery folder is not a private app-owned directory."
        case .directoryChanged:
            return "The recording recovery folder changed while it was in use."
        }
    }
}

public struct PendingRecordingStore: Sendable {
    public let directoryURL: URL

    private let trustedBaseDirectoryURL: URL
    private let managedDirectoryComponents: [String]
    private let directoryTrust = PendingRecordingDirectoryTrust()

    public init(directoryURL: URL? = nil) {
        if let directoryURL {
            let standardizedURL = directoryURL.standardizedFileURL
            self.directoryURL = standardizedURL
            trustedBaseDirectoryURL = standardizedURL.deletingLastPathComponent()
            managedDirectoryComponents = [standardizedURL.lastPathComponent]
        } else {
            let baseURL = Self.defaultBaseDirectoryURL().standardizedFileURL
            trustedBaseDirectoryURL = baseURL
            managedDirectoryComponents = ["CaptureStudio", "PendingRecordings"]
            self.directoryURL = managedDirectoryComponents.reduce(baseURL) { directory, component in
                directory.appendingPathComponent(component, isDirectory: true)
            }
        }
    }

    init(baseDirectoryURL: URL, managedDirectoryComponents: [String]) {
        precondition(!managedDirectoryComponents.isEmpty)
        precondition(managedDirectoryComponents.allSatisfy(Self.isSafePathComponent))
        let standardizedBaseURL = baseDirectoryURL.standardizedFileURL
        trustedBaseDirectoryURL = standardizedBaseURL
        self.managedDirectoryComponents = managedDirectoryComponents
        directoryURL = managedDirectoryComponents.reduce(standardizedBaseURL) { directory, component in
            directory.appendingPathComponent(component, isDirectory: true)
        }
    }

    public func allocateRecordingURL() throws -> URL {
        guard try validateDirectory(createIfNeeded: true, restrictPermissions: true) != nil else {
            throw PendingRecordingStoreError.unsafeDirectory
        }
        return directoryURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
    }

    public func recoverableRecordings() throws -> [PendingRecording] {
        guard try validateDirectory(createIfNeeded: false, restrictPermissions: true) != nil else {
            return []
        }

        let propertyKeys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .creationDateKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(propertyKeys),
            options: [.skipsHiddenFiles]
        )

        let recordings: [PendingRecording] = urls.compactMap { url -> PendingRecording? in
            let ownedURL = directoryURL.appendingPathComponent(url.lastPathComponent)
            guard owns(url),
                  let values = try? url.resourceValues(forKeys: propertyKeys),
                  isPrivateOwnedRegularFile(ownedURL),
                  let identity = try? CaptureFileIdentity.existingFile(at: ownedURL)
            else {
                return nil
            }

            return PendingRecording(
                fileURL: ownedURL,
                createdAt: values.contentModificationDate ?? values.creationDate ?? .distantPast,
                fileIdentity: identity
            )
        }

        guard try validateDirectory(createIfNeeded: false, restrictPermissions: true) != nil else {
            throw PendingRecordingStoreError.directoryChanged
        }
        return recordings.sorted { $0.createdAt > $1.createdAt }
    }

    public func owns(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL.deletingLastPathComponent() == directoryURL,
              standardizedURL.pathExtension.lowercased() == "mp4",
              UUID(uuidString: standardizedURL.deletingPathExtension().lastPathComponent) != nil,
              (try? validateDirectory(createIfNeeded: false, restrictPermissions: true)) != nil
        else {
            return false
        }
        return true
    }

    private func validateDirectory(
        createIfNeeded: Bool,
        restrictPermissions: Bool
    ) throws -> PendingRecordingDirectoryIdentity? {
        guard let identity = try openManagedDirectory(
            createIfNeeded: createIfNeeded,
            restrictPermissions: restrictPermissions
        ) else {
            return nil
        }
        guard directoryTrust.accept(identity) else {
            throw PendingRecordingStoreError.directoryChanged
        }
        return identity
    }

    private func openManagedDirectory(
        createIfNeeded: Bool,
        restrictPermissions: Bool
    ) throws -> PendingRecordingDirectoryIdentity? {
        if createIfNeeded {
            try FileManager.default.createDirectory(
                at: trustedBaseDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let baseDescriptor = trustedBaseDirectoryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard baseDescriptor >= 0 else {
            if !createIfNeeded, errno == ENOENT {
                return nil
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var currentDescriptor = baseDescriptor
        defer { Darwin.close(currentDescriptor) }

        var baseInformation = stat()
        guard Darwin.fstat(currentDescriptor, &baseInformation) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard baseInformation.st_mode & S_IFMT == S_IFDIR,
              baseInformation.st_uid == Darwin.geteuid()
        else {
            throw PendingRecordingStoreError.unsafeDirectory
        }

        for component in managedDirectoryComponents {
            if createIfNeeded {
                let createResult = component.withCString { name in
                    Darwin.mkdirat(currentDescriptor, name, S_IRWXU)
                }
                if createResult != 0, errno != EEXIST {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }

            let nextDescriptor = component.withCString { name in
                Darwin.openat(
                    currentDescriptor,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            guard nextDescriptor >= 0 else {
                if !createIfNeeded, errno == ENOENT {
                    return nil
                }
                if errno == ELOOP || errno == ENOTDIR {
                    throw PendingRecordingStoreError.unsafeDirectory
                }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }

            Darwin.close(currentDescriptor)
            currentDescriptor = nextDescriptor

            var information = stat()
            guard Darwin.fstat(currentDescriptor, &information) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard information.st_mode & S_IFMT == S_IFDIR,
                  information.st_uid == Darwin.geteuid()
            else {
                throw PendingRecordingStoreError.unsafeDirectory
            }
            if restrictPermissions,
               Darwin.fchmod(currentDescriptor, S_IRWXU) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }

        var information = stat()
        guard Darwin.fstat(currentDescriptor, &information) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return PendingRecordingDirectoryIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino),
            owner: information.st_uid
        )
    }

    private static func defaultBaseDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private static func isSafePathComponent(_ component: String) -> Bool {
        !component.isEmpty && component != "." && component != ".." && !component.contains("/")
    }

    private func isPrivateOwnedRegularFile(_ fileURL: URL) -> Bool {
        var information = stat()
        let result = fileURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                return -1
            }
            return Darwin.lstat(path, &information)
        }
        guard result == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_uid == Darwin.geteuid(),
              information.st_size > 0
        else {
            return false
        }
        return information.st_mode & (S_IWGRP | S_IWOTH) == 0
    }
}

private struct PendingRecordingDirectoryIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let owner: uid_t
}

private final class PendingRecordingDirectoryTrust: @unchecked Sendable {
    private let lock = NSLock()
    private var identity: PendingRecordingDirectoryIdentity?

    func accept(_ candidate: PendingRecordingDirectoryIdentity) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let identity {
            return identity == candidate
        }
        identity = candidate
        return true
    }
}
