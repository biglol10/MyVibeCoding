public protocol IndexSearching: Sendable {
    func search(
        request: SearchRequest,
        limit: Int,
        after cursor: SearchPageCursor?
    ) async throws -> SearchPage
}

extension SQLiteIndexReader: IndexSearching {}
