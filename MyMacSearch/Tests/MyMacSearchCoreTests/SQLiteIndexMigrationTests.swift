import Foundation
import SQLite3
import XCTest
@testable import MyMacSearchCore

final class SQLiteIndexMigrationTests: XCTestCase {
    func testVersionOneMigrationPreservesEntriesFTSAndCheckpoint() throws {
        let fixture = try VersionOneIndexFixture()
        defer { fixture.remove() }

        _ = try SQLiteIndexWriter(databaseURL: fixture.databaseURL)

        XCTAssertEqual(try fixture.integer("PRAGMA user_version"), 2)
        XCTAssertEqual(try fixture.texts("SELECT path FROM entries"), ["/Users/test/report.swift"])
        XCTAssertEqual(
            try fixture.texts(
                "SELECT entries.path FROM entries_fts JOIN entries ON entries.id = entries_fts.rowid WHERE entries_fts MATCH 'report'"
            ),
            ["/Users/test/report.swift"]
        )
        XCTAssertEqual(try fixture.integer("SELECT last_event_id FROM scopes WHERE id = 'home'"), 42)
        XCTAssertTrue(try fixture.hasColumn(table: "scopes", name: "last_completed_scan_at"))
        XCTAssertTrue(try fixture.hasTable("index_issues"))
    }

    func testNewerSchemaIsRejectedWithoutDowngrade() throws {
        let fixture = try VersionOneIndexFixture(userVersion: 99)
        defer { fixture.remove() }

        XCTAssertThrowsError(try SQLiteIndexWriter(databaseURL: fixture.databaseURL)) { error in
            guard case SQLiteIndexError.invalidData = error else {
                return XCTFail("Expected invalidData, got \(error)")
            }
        }
        XCTAssertEqual(try fixture.integer("PRAGMA user_version"), 99)
    }
}

private struct VersionOneIndexFixture {
    let rootURL: URL
    let databaseURL: URL

    init(userVersion: Int = 1) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacSearchMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        databaseURL = rootURL.appendingPathComponent("index.sqlite3")
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw SQLiteIndexError.openFailed("fixture")
        }
        defer { sqlite3_close(database) }
        try execute(
            """
            PRAGMA user_version = \(userVersion);
            CREATE TABLE scopes (
              id TEXT PRIMARY KEY, root_path TEXT NOT NULL, volume_type TEXT NOT NULL,
              is_enabled INTEGER NOT NULL, active_generation INTEGER,
              completed_generation INTEGER NOT NULL DEFAULT 0, last_event_id INTEGER
            );
            CREATE TABLE entries (
              id INTEGER PRIMARY KEY, scope_id TEXT NOT NULL, path TEXT NOT NULL UNIQUE,
              parent_path TEXT NOT NULL, name TEXT NOT NULL, search_name TEXT NOT NULL,
              search_path TEXT NOT NULL, extension TEXT NOT NULL, kind TEXT NOT NULL,
              size_bytes INTEGER NOT NULL, modified_at REAL NOT NULL,
              is_directory INTEGER NOT NULL, is_symlink INTEGER NOT NULL,
              is_package INTEGER NOT NULL, is_hidden INTEGER NOT NULL,
              device_id INTEGER, inode INTEGER, scan_generation INTEGER NOT NULL
            );
            CREATE VIRTUAL TABLE entries_fts USING fts5(
              search_name, search_path, content='entries', content_rowid='id', tokenize='trigram'
            );
            INSERT INTO scopes VALUES ('home', '/Users/test', 'internalLocal', 1, NULL, 7, 42);
            INSERT INTO entries VALUES (
              1, 'home', '/Users/test/report.swift', '/Users/test', 'report.swift',
              'report.swift', '/users/test/report.swift', 'swift', 'code', 100, 100,
              0, 0, 0, 0, NULL, NULL, 7
            );
            INSERT INTO entries_fts(rowid, search_name, search_path)
              VALUES (1, 'report.swift', '/users/test/report.swift');
            """,
            database: database
        )
    }

    func remove() { try? FileManager.default.removeItem(at: rootURL) }

    func integer(_ sql: String) throws -> Int {
        Int(try scalar(sql) { sqlite3_column_int64($0, 0) })
    }

    func texts(_ sql: String) throws -> [String] {
        var values: [String] = []
        try query(sql) { statement in
            guard let text = sqlite3_column_text(statement, 0) else { return }
            values.append(String(cString: text))
        }
        return values
    }

    func hasTable(_ name: String) throws -> Bool {
        try texts("SELECT name FROM sqlite_master WHERE type = 'table' AND name = '\(name)'").count == 1
    }

    func hasColumn(table: String, name: String) throws -> Bool {
        try texts("SELECT name FROM pragma_table_info('\(table)')").contains(name)
    }

    private func scalar<T>(_ sql: String, read: (OpaquePointer) -> T) throws -> T {
        var output: T?
        try query(sql) { output = read($0) }
        return try XCTUnwrap(output)
    }

    private func query(_ sql: String, row: (OpaquePointer) throws -> Void) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw SQLiteIndexError.openFailed("fixture read")
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteIndexError.prepareFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW { try row(statement) }
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
            defer { sqlite3_free(message) }
            throw SQLiteIndexError.executeFailed(message.map { String(cString: $0) } ?? "fixture write")
        }
    }
}
