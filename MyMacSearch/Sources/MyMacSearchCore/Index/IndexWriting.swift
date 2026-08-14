public protocol IndexWriting: Sendable {
    func beginScopeScan(_ scope: IndexScope, generation: Int64) async throws
    func upsertBatch(
        _ entries: [IndexedEntry],
        scopeID: String,
        generation: Int64
    ) async throws
    func delete(path: String) async throws
    func completeScopeScan(scopeID: String, generation: Int64) async throws
    func updateEventCheckpoint(scopeID: String, eventID: UInt64) async throws
}

extension SQLiteIndexWriter: IndexWriting {}
