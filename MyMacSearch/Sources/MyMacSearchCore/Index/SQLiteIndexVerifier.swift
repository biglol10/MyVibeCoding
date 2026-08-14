import Foundation
import SQLite3

public actor SQLiteIndexVerifier: IndexVerifying {
    private let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public func verify() throws -> IndexVerificationResult {
        let startedAt = Date()
        let connection = try SQLiteConnection(
            path: databaseURL.path,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        )
        var checks: [IndexVerificationCheck] = []

        let schemaVersion = try scalarInt(connection, sql: "PRAGMA user_version")
        checks.append(IndexVerificationCheck(
            name: "Schema",
            passed: schemaVersion == 2,
            detail: schemaVersion == 2 ? "Schema version 2" : "Expected schema 2, found \(schemaVersion)"
        ))

        let quickCheck = try scalarText(connection, sql: "PRAGMA quick_check")
        checks.append(IndexVerificationCheck(
            name: "SQLite",
            passed: quickCheck == "ok",
            detail: quickCheck
        ))

        do {
            try connection.execute("INSERT INTO entries_fts(entries_fts, rank) VALUES('integrity-check', 1)")
            checks.append(IndexVerificationCheck(name: "FTS5", passed: true, detail: "FTS5 integrity check passed"))
        } catch {
            checks.append(IndexVerificationCheck(name: "FTS5", passed: false, detail: error.localizedDescription))
        }

        let entries = try scalarInt(connection, sql: "SELECT COUNT(*) FROM entries")
        let ftsEntries = try scalarInt(connection, sql: "SELECT COUNT(*) FROM entries_fts")
        checks.append(IndexVerificationCheck(
            name: "Entry consistency",
            passed: entries == ftsEntries,
            detail: "Entries: \(entries), FTS rows: \(ftsEntries)"
        ))
        return IndexVerificationResult(startedAt: startedAt, completedAt: Date(), checks: checks)
    }

    private func scalarInt(_ connection: SQLiteConnection, sql: String) throws -> Int64 {
        let statement = try connection.prepare(sql)
        guard try statement.step() == SQLITE_ROW else {
            throw SQLiteIndexError.invalidData("No result for \(sql)")
        }
        return statement.int64(at: 0)
    }

    private func scalarText(_ connection: SQLiteConnection, sql: String) throws -> String {
        let statement = try connection.prepare(sql)
        guard try statement.step() == SQLITE_ROW else {
            throw SQLiteIndexError.invalidData("No result for \(sql)")
        }
        return try statement.text(at: 0)
    }
}
