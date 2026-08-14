import Foundation

public enum IndexedFileKind: String, CaseIterable, Codable, Sendable {
    case folder
    case application
    case pdf
    case image
    case video
    case audio
    case archive
    case code
    case document
    case other
}

public struct IndexedEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: Int64
    public let scopeID: String
    public let path: String
    public let parentPath: String
    public let name: String
    public let searchName: String
    public let searchPath: String
    public let fileExtension: String
    public let kind: IndexedFileKind
    public let sizeBytes: Int64
    public let modifiedAt: Date
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let isPackage: Bool
    public let isHidden: Bool
    public let deviceID: UInt64?
    public let inode: UInt64?
    public let scanGeneration: Int64

    public init(
        id: Int64 = 0,
        scopeID: String,
        path: String,
        parentPath: String,
        name: String,
        searchName: String? = nil,
        searchPath: String? = nil,
        fileExtension: String,
        kind: IndexedFileKind,
        sizeBytes: Int64,
        modifiedAt: Date,
        isDirectory: Bool,
        isSymlink: Bool,
        isPackage: Bool,
        isHidden: Bool,
        deviceID: UInt64? = nil,
        inode: UInt64? = nil,
        scanGeneration: Int64
    ) {
        self.id = id
        self.scopeID = scopeID
        self.path = path
        self.parentPath = parentPath
        self.name = name
        self.searchName = searchName ?? SearchTextNormalizer.normalize(name)
        self.searchPath = searchPath ?? SearchTextNormalizer.normalize(path)
        self.fileExtension = fileExtension.lowercased()
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.deviceID = deviceID
        self.inode = inode
        self.scanGeneration = scanGeneration
    }
}

public enum IndexedVolumeType: String, Codable, Sendable {
    case internalLocal
    case external
    case network
}

public struct IndexScope: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var rootPath: String
    public var volumeType: IndexedVolumeType
    public var isEnabled: Bool
    public var completedGeneration: Int64
    public var lastEventID: UInt64?

    public init(
        id: String,
        rootPath: String,
        volumeType: IndexedVolumeType = .internalLocal,
        isEnabled: Bool = true,
        completedGeneration: Int64 = 0,
        lastEventID: UInt64? = nil
    ) {
        self.id = id
        self.rootPath = rootPath
        self.volumeType = volumeType
        self.isEnabled = isEnabled
        self.completedGeneration = completedGeneration
        self.lastEventID = lastEventID
    }
}

public enum IndexStatus: Equatable, Sendable {
    case initialScan
    case watching
    case paused
    case permissionNeeded
    case error(message: String)
}

public struct IndexProgress: Equatable, Sendable {
    public var scannedCount: Int
    public var skippedCount: Int
    public var permissionDeniedCount: Int
    public var currentPath: String?
    public var processedDirectories: Int
    public var queuedDirectories: Int

    public init(
        scannedCount: Int = 0,
        skippedCount: Int = 0,
        permissionDeniedCount: Int = 0,
        currentPath: String? = nil,
        processedDirectories: Int = 0,
        queuedDirectories: Int = 0
    ) {
        self.scannedCount = scannedCount
        self.skippedCount = skippedCount
        self.permissionDeniedCount = permissionDeniedCount
        self.currentPath = currentPath
        self.processedDirectories = processedDirectories
        self.queuedDirectories = queuedDirectories
    }

    public var estimatedFraction: Double? {
        let discovered = processedDirectories + queuedDirectories
        guard discovered > 0 else { return nil }
        return Double(processedDirectories) / Double(discovered)
    }
}

public struct SearchCursor: Codable, Equatable, Sendable {
    public let rank: Double
    public let modifiedAt: Date
    public let entryID: Int64

    public init(rank: Double, modifiedAt: Date, entryID: Int64) {
        self.rank = rank
        self.modifiedAt = modifiedAt
        self.entryID = entryID
    }
}

public struct SearchPage: Equatable, Sendable {
    public let entries: [IndexedEntry]
    public let nextCursor: SearchCursor?

    public init(entries: [IndexedEntry], nextCursor: SearchCursor?) {
        self.entries = entries
        self.nextCursor = nextCursor
    }
}

public enum SearchTextNormalizer {
    public static func normalize(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}
