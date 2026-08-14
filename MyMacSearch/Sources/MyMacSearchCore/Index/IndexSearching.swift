public protocol IndexSearching: Sendable {
    func search(
        query: SearchQuery,
        limit: Int,
        after cursor: SearchCursor?
    ) async throws -> SearchPage
}

extension SQLiteIndexReader: IndexSearching {}
