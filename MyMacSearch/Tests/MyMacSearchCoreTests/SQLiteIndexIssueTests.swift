import Foundation
import SQLite3
import XCTest
@testable import MyMacSearchCore

final class SQLiteIndexIssueTests: XCTestCase {
    func testRepeatedIssueCoalescesAndResolutionKeepsHistory() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)

        try await fixture.writer.recordIssue(
            scopeID: "home",
            path: "/private",
            category: .permissionDenied,
            message: "Permission denied",
            occurredAt: first
        )
        try await fixture.writer.recordIssue(
            scopeID: "home",
            path: "/private",
            category: .permissionDenied,
            message: "Still denied",
            occurredAt: second
        )

        var row = try issueRow(at: fixture.databaseURL)
        XCTAssertEqual(row.count, 2)
        XCTAssertEqual(row.message, "Still denied")
        XCTAssertEqual(row.lastSeenAt, 200)
        XCTAssertNil(row.resolvedAt)

        try await fixture.writer.resolveIssues(scopeID: "home", resolvedAt: second)
        row = try issueRow(at: fixture.databaseURL)
        XCTAssertEqual(row.resolvedAt, 200)
    }

    func testScanAndEventTimestampsAreCommittedWithState() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "home", rootPath: "/Users/test")
        let scanDate = Date(timeIntervalSince1970: 300)
        let eventDate = Date(timeIntervalSince1970: 400)

        try await fixture.writer.beginScopeScan(scope, generation: 8)
        try await fixture.writer.completeScopeScan(scopeID: scope.id, generation: 8, completedAt: scanDate)
        try await fixture.writer.updateEventCheckpoint(scopeID: scope.id, eventID: 91, occurredAt: eventDate)

        let values = try scopeDates(at: fixture.databaseURL)
        XCTAssertEqual(values.scan, 300)
        XCTAssertEqual(values.event, 400)
        XCTAssertEqual(values.eventID, 91)
    }

    private func issueRow(at url: URL) throws -> (count: Int, message: String, lastSeenAt: Double, resolvedAt: Double?) {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            throw SQLiteIndexError.openFailed("test read")
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        let sql = "SELECT occurrence_count, message, last_seen_at, resolved_at FROM index_issues"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement,
              sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteIndexError.invalidData("missing issue")
        }
        defer { sqlite3_finalize(statement) }
        let message = String(cString: sqlite3_column_text(statement, 1))
        let resolved = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3)
        return (Int(sqlite3_column_int64(statement, 0)), message, sqlite3_column_double(statement, 2), resolved)
    }

    private func scopeDates(at url: URL) throws -> (scan: Double, event: Double, eventID: Int64) {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            throw SQLiteIndexError.openFailed("test read")
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT last_completed_scan_at, last_event_at, last_event_id FROM scopes WHERE id = 'home'",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement, sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteIndexError.invalidData("missing scope")
        }
        defer { sqlite3_finalize(statement) }
        return (
            sqlite3_column_double(statement, 0),
            sqlite3_column_double(statement, 1),
            sqlite3_column_int64(statement, 2)
        )
    }
}
