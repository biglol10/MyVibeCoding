import Foundation

public enum SearchSort: String, CaseIterable, Codable, Sendable {
    case relevance
    case nameAscending
    case nameDescending
    case pathAscending
    case pathDescending
    case modifiedNewest
    case modifiedOldest
    case sizeLargest
    case sizeSmallest
    case kindThenName
}

public struct SearchRequest: Equatable, Sendable {
    public var query: SearchQuery
    public var sort: SearchSort

    public init(query: SearchQuery, sort: SearchSort) {
        self.query = query
        self.sort = sort
    }
}

public enum SearchPageCursor: Codable, Equatable, Sendable {
    case relevance(rank: Double, modifiedAt: Date, entryID: Int64)
    case text(value: String, entryID: Int64)
    case date(value: Date, entryID: Int64)
    case size(value: Int64, entryID: Int64)
    case kind(kind: String, name: String, entryID: Int64)
}
