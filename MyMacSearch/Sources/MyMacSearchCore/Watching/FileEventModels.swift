import Foundation

public struct FileEventFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let created = FileEventFlags(rawValue: 1 << 0)
    public static let removed = FileEventFlags(rawValue: 1 << 1)
    public static let renamed = FileEventFlags(rawValue: 1 << 2)
    public static let modified = FileEventFlags(rawValue: 1 << 3)
    public static let mustScanSubDirectories = FileEventFlags(rawValue: 1 << 4)
    public static let userDropped = FileEventFlags(rawValue: 1 << 5)
    public static let kernelDropped = FileEventFlags(rawValue: 1 << 6)
    public static let eventIDsWrapped = FileEventFlags(rawValue: 1 << 7)
    public static let rootChanged = FileEventFlags(rawValue: 1 << 8)
}

public struct FileEvent: Equatable, Sendable {
    public let path: String
    public let eventID: UInt64
    public let flags: FileEventFlags

    public init(path: String, eventID: UInt64, flags: FileEventFlags) {
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.eventID = eventID
        self.flags = flags
    }
}

public struct FileEventPlan: Equatable, Sendable {
    public var upsertPaths: Set<String>
    public var deletePaths: Set<String>
    public var reconcileRoots: Set<String>
    public var latestEventID: UInt64?
    public var requiresFullReconciliation: Bool

    public init(
        upsertPaths: Set<String> = [],
        deletePaths: Set<String> = [],
        reconcileRoots: Set<String> = [],
        latestEventID: UInt64? = nil,
        requiresFullReconciliation: Bool = false
    ) {
        self.upsertPaths = upsertPaths
        self.deletePaths = deletePaths
        self.reconcileRoots = reconcileRoots
        self.latestEventID = latestEventID
        self.requiresFullReconciliation = requiresFullReconciliation
    }
}
