import Foundation

public protocol IndexWriting: Sendable {
    func beginScopeScan(_ scope: IndexScope, generation: Int64) async throws
    func upsertBatch(
        _ entries: [IndexedEntry],
        scopeID: String,
        generation: Int64
    ) async throws
    func delete(path: String) async throws
    func completeScopeScan(scopeID: String, generation: Int64, completedAt: Date) async throws
    func updateEventCheckpoint(scopeID: String, eventID: UInt64, occurredAt: Date) async throws
    func recordIssue(
        scopeID: String,
        path: String,
        category: IndexIssueCategory,
        message: String,
        occurredAt: Date
    ) async throws
    func resolveIssues(scopeID: String, resolvedAt: Date) async throws
}

extension SQLiteIndexWriter: IndexWriting {}

public extension IndexWriting {
    func completeScopeScan(scopeID: String, generation: Int64) async throws {
        try await completeScopeScan(scopeID: scopeID, generation: generation, completedAt: Date())
    }

    func updateEventCheckpoint(scopeID: String, eventID: UInt64) async throws {
        try await updateEventCheckpoint(scopeID: scopeID, eventID: eventID, occurredAt: Date())
    }
}
