public enum ByteSizeRange: Equatable, Sendable {
    case greaterThan(Int64)
    case atLeast(Int64)
    case lessThan(Int64)
    case atMost(Int64)
    case closed(Int64, Int64)
}

public struct SearchQueryToken: Equatable, Identifiable, Sendable {
    public var id: Int { characterRange.lowerBound }
    public let filter: String
    public let rawText: String
    public let characterRange: Range<Int>

    public init(filter: String, rawText: String, characterRange: Range<Int>) {
        self.filter = filter
        self.rawText = rawText
        self.characterRange = characterRange
    }
}

public struct ParsedSearchQuery: Equatable, Sendable {
    public let query: SearchQuery
    public let tokens: [SearchQueryToken]

    public init(query: SearchQuery, tokens: [SearchQueryToken]) {
        self.query = query
        self.tokens = tokens
    }
}
