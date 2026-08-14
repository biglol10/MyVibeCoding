import Foundation
import MyMacSearchCore

public struct RecentSearch: Codable, Equatable, Identifiable, Sendable {
    public var id: String { query }
    public let query: String
    public let sort: SearchSort
    public let lastUsedAt: Date

    public init(query: String, sort: SearchSort, lastUsedAt: Date) {
        self.query = query
        self.sort = sort
        self.lastUsedAt = lastUsedAt
    }
}

public struct SavedSearch: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var query: String
    public var sort: SearchSort
    public let createdAt: Date
    public var lastUsedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        query: String,
        sort: SearchSort,
        createdAt: Date,
        lastUsedAt: Date
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.sort = sort
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

public struct SearchLibrary: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var recent: [RecentSearch]
    public var saved: [SavedSearch]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        recent: [RecentSearch] = [],
        saved: [SavedSearch] = []
    ) {
        self.schemaVersion = schemaVersion
        self.recent = recent
        self.saved = saved
    }
}

public enum SearchLibraryError: Error, LocalizedError, Equatable, Sendable {
    case corruptLibrary
    case unsupportedSchema(Int)
    case invalidName
    case invalidQuery
    case missingSavedSearch

    public var errorDescription: String? {
        switch self {
        case .corruptLibrary: "The saved search library could not be read."
        case .unsupportedSchema(let version): "Unsupported saved search library version: \(version)."
        case .invalidName: "Saved search name cannot be empty."
        case .invalidQuery: "Saved search query cannot be empty."
        case .missingSavedSearch: "The saved search no longer exists."
        }
    }
}
