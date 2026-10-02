import Foundation

public struct FolderAccessGrantID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct FolderAccessGrant: Codable, Equatable, Identifiable, Sendable {
    public var id: FolderAccessGrantID
    public var url: URL
    public var bookmarkData: Data
    public var createdAt: Date
    public var lastResolvedAt: Date?

    public init(
        id: FolderAccessGrantID = FolderAccessGrantID(),
        url: URL,
        bookmarkData: Data,
        createdAt: Date = Date(),
        lastResolvedAt: Date? = nil
    ) {
        self.id = id
        self.url = url.standardizedFileURL
        self.bookmarkData = bookmarkData
        self.createdAt = createdAt
        self.lastResolvedAt = lastResolvedAt
    }

    public var displayPath: String {
        url.path
    }
}

public enum FolderAccessGrantAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case unknown
}

public struct FolderAccessGrantSummary: Equatable, Identifiable, Sendable {
    public var id: FolderAccessGrantID
    public var url: URL
    public var displayPath: String
    public var availability: FolderAccessGrantAvailability
    public var isStale: Bool

    public init(
        grant: FolderAccessGrant,
        availability: FolderAccessGrantAvailability = .unknown,
        isStale: Bool = false
    ) {
        self.id = grant.id
        self.url = grant.url
        self.displayPath = grant.displayPath
        self.availability = availability
        self.isStale = isStale
    }
}
