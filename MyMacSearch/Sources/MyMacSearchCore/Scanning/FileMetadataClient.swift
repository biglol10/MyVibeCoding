import Darwin
import Foundation

public struct FileMetadata: Equatable, Sendable {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let isPackage: Bool
    public let isHidden: Bool
    public let sizeBytes: Int64
    public let modifiedAt: Date
    public let deviceID: UInt64?
    public let inode: UInt64?

    public init(
        path: String,
        name: String,
        isDirectory: Bool,
        isSymlink: Bool,
        isPackage: Bool,
        isHidden: Bool,
        sizeBytes: Int64,
        modifiedAt: Date,
        deviceID: UInt64?,
        inode: UInt64?
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
        self.inode = inode
    }
}

public enum FileMetadataClientError: Error, LocalizedError, Equatable, Sendable {
    case permissionDenied(String)
    case missing(String)
    case readFailed(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .missing(let path):
            return "Path is no longer available: \(path)"
        case .readFailed(let path, let message):
            return "Could not read \(path): \(message)"
        }
    }
}

public protocol FileMetadataClient: Sendable {
    func metadata(at url: URL) async throws -> FileMetadata
    func children(of directoryURL: URL) async throws -> [URL]
}

public actor FoundationFileMetadataClient: FileMetadataClient {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func metadata(at url: URL) async throws -> FileMetadata {
        let standardized = url.standardizedFileURL
        do {
            let values = try standardized.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isPackageKey,
                .isHiddenKey,
                .fileSizeKey,
                .contentModificationDateKey
            ])
            let identity = Self.identity(path: standardized.path)
            return FileMetadata(
                path: standardized.path,
                name: standardized.lastPathComponent,
                isDirectory: values.isDirectory ?? false,
                isSymlink: values.isSymbolicLink ?? false,
                isPackage: values.isPackage ?? false,
                isHidden: values.isHidden ?? standardized.lastPathComponent.hasPrefix("."),
                sizeBytes: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast,
                deviceID: identity?.device,
                inode: identity?.inode
            )
        } catch {
            throw Self.map(error: error, path: standardized.path)
        }
    }

    public func children(of directoryURL: URL) async throws -> [URL] {
        let standardized = directoryURL.standardizedFileURL
        do {
            return try fileManager.contentsOfDirectory(
                at: standardized,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw Self.map(error: error, path: standardized.path)
        }
    }

    private static func identity(path: String) -> (device: UInt64, inode: UInt64)? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (UInt64(info.st_dev), UInt64(info.st_ino))
    }

    private static func map(error: Error, path: String) -> FileMetadataClientError {
        let nsError = error as NSError
        if (nsError.domain == NSCocoaErrorDomain
            && (nsError.code == CocoaError.fileReadNoPermission.rawValue
                || nsError.code == CocoaError.fileWriteNoPermission.rawValue))
            || (nsError.domain == NSPOSIXErrorDomain
                && (nsError.code == Int(EACCES) || nsError.code == Int(EPERM))) {
            return .permissionDenied(path)
        }
        if (nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.fileNoSuchFile.rawValue)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)) {
            return .missing(path)
        }
        return .readFailed(path: path, message: error.localizedDescription)
    }
}
