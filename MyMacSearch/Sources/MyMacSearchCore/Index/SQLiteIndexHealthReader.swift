import Foundation
import SQLite3

public actor SQLiteIndexHealthReader: IndexHealthReading {
    private let databaseURL: URL

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        let connection = try SQLiteConnection(
            path: databaseURL.path,
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        )
        let statement = try connection.prepare("SELECT 1 FROM scopes LIMIT 1")
        _ = try statement.step()
    }

    public func snapshot(liveStates: [String: ScopeRuntimeState]) throws -> IndexHealthSnapshot {
        let connection = try readConnection()
        let statement = try connection.prepare(
            """
            SELECT
              s.id, s.root_path, s.volume_type, s.is_enabled,
              COALESCE(entry_counts.entry_count, 0),
              s.last_completed_scan_at, s.last_event_at, s.last_event_id,
              COALESCE(issues_by_scope.issue_count, 0), s.last_error,
              s.last_skipped_count, s.last_permission_denied_count
            FROM scopes s
            LEFT JOIN scope_entry_counts entry_counts ON entry_counts.scope_id = s.id
            LEFT JOIN (
              SELECT scope_id, COUNT(*) AS issue_count
              FROM index_issues WHERE resolved_at IS NULL GROUP BY scope_id
            ) issues_by_scope ON issues_by_scope.scope_id = s.id
            ORDER BY s.root_path ASC
            """
        )
        var scopes: [IndexScopeHealth] = []
        var total = 0
        while try statement.step() == SQLITE_ROW {
            let id = try statement.text(at: 0)
            guard let volumeType = IndexedVolumeType(rawValue: try statement.text(at: 2)) else {
                throw SQLiteIndexError.invalidData("Unknown volume type for scope \(id)")
            }
            let count = Int(statement.int64(at: 4))
            total += count
            let live = liveStates[id]
            let enabled = statement.int64(at: 3) == 1
            scopes.append(
                IndexScopeHealth(
                    scopeID: id,
                    rootPath: try statement.text(at: 1),
                    volumeType: volumeType,
                    isEnabled: enabled,
                    state: live?.state ?? (enabled ? .paused : .disabled),
                    entryCount: count,
                    lastCompletedScanAt: statement.optionalDouble(at: 5).map(Date.init(timeIntervalSince1970:)),
                    lastEventAt: statement.optionalDouble(at: 6).map(Date.init(timeIntervalSince1970:)),
                    lastEventID: statement.optionalInt64(at: 7).map { UInt64(bitPattern: $0) },
                    progress: live?.progress ?? IndexProgress(),
                    lastSkippedCount: Int(statement.int64(at: 10)),
                    lastPermissionDeniedCount: Int(statement.int64(at: 11)),
                    unresolvedIssueCount: Int(statement.int64(at: 8)),
                    lastError: live?.message ?? statement.optionalText(at: 9)
                )
            )
        }
        let databaseBytes = fileSize(databaseURL)
        let auxiliaryBytes = fileSize(URL(fileURLWithPath: databaseURL.path + "-wal"))
            + fileSize(URL(fileURLWithPath: databaseURL.path + "-shm"))
        return IndexHealthSnapshot(
            scopes: scopes,
            totalEntryCount: total,
            databaseBytes: databaseBytes,
            auxiliaryBytes: auxiliaryBytes
        )
    }

    public func issues(scopeID: String?, unresolvedOnly: Bool, limit: Int) throws -> [IndexIssueRecord] {
        let boundedLimit = min(max(limit, 1), 500)
        var predicates: [String] = []
        var bindings: [SQLiteBindValue] = []
        if let scopeID {
            predicates.append("scope_id = ?")
            bindings.append(.text(scopeID))
        }
        if unresolvedOnly {
            predicates.append("resolved_at IS NULL")
        }
        let filter = predicates.isEmpty ? "" : "WHERE " + predicates.joined(separator: " AND ")
        let connection = try readConnection()
        let statement = try connection.prepare(
            """
            SELECT id, scope_id, path, category, message, first_seen_at, last_seen_at,
                   occurrence_count, resolved_at
            FROM index_issues
            \(filter)
            ORDER BY last_seen_at DESC, id DESC
            LIMIT ?
            """
        )
        bindings.append(.int64(Int64(boundedLimit)))
        try statement.bind(bindings)
        var records: [IndexIssueRecord] = []
        while try statement.step() == SQLITE_ROW {
            guard let category = IndexIssueCategory(rawValue: try statement.text(at: 3)) else {
                throw SQLiteIndexError.invalidData("Unknown index issue category")
            }
            records.append(
                IndexIssueRecord(
                    id: statement.int64(at: 0),
                    scopeID: try statement.text(at: 1),
                    path: try statement.text(at: 2),
                    category: category,
                    message: try statement.text(at: 4),
                    firstSeenAt: Date(timeIntervalSince1970: statement.double(at: 5)),
                    lastSeenAt: Date(timeIntervalSince1970: statement.double(at: 6)),
                    occurrenceCount: Int(statement.int64(at: 7)),
                    resolvedAt: statement.optionalDouble(at: 8).map(Date.init(timeIntervalSince1970:))
                )
            )
        }
        return records
    }

    private func readConnection() throws -> SQLiteConnection {
        try SQLiteConnection(
            path: databaseURL.path,
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        )
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
