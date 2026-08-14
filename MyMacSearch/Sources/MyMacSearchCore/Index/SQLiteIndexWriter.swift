import Foundation
import SQLite3

public actor SQLiteIndexWriter {
    private let databaseURL: URL

    public init(databaseURL: URL) throws {
        try FTS5CapabilityProbe.verify()
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.databaseURL = databaseURL
        try Self.initializeSchema(at: databaseURL)
    }

    public func beginScopeScan(_ scope: IndexScope, generation: Int64) throws {
        let connection = try writableConnection()
        let statement = try connection.prepare(
            """
            INSERT INTO scopes(id, root_path, volume_type, is_enabled, active_generation, completed_generation, last_event_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              root_path = excluded.root_path,
              volume_type = excluded.volume_type,
              is_enabled = excluded.is_enabled,
              active_generation = excluded.active_generation,
              last_event_id = excluded.last_event_id
            """
        )
        try statement.bind([
            .text(scope.id),
            .text(scope.rootPath),
            .text(scope.volumeType.rawValue),
            .int64(scope.isEnabled ? 1 : 0),
            .int64(generation),
            .int64(scope.completedGeneration),
            scope.lastEventID.map { .int64(Int64(bitPattern: $0)) } ?? .null
        ])
        _ = try statement.step()
    }

    public func upsertBatch(
        _ entries: [IndexedEntry],
        scopeID: String,
        generation: Int64
    ) throws {
        guard !entries.isEmpty else { return }
        let connection = try writableConnection()
        try connection.transaction {
            let statement = try connection.prepare(
                """
                INSERT INTO entries(
                  scope_id, path, parent_path, name, search_name, search_path, extension, kind,
                  size_bytes, modified_at, is_directory, is_symlink, is_package, is_hidden,
                  device_id, inode, scan_generation
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET
                  scope_id = excluded.scope_id,
                  parent_path = excluded.parent_path,
                  name = excluded.name,
                  search_name = excluded.search_name,
                  search_path = excluded.search_path,
                  extension = excluded.extension,
                  kind = excluded.kind,
                  size_bytes = excluded.size_bytes,
                  modified_at = excluded.modified_at,
                  is_directory = excluded.is_directory,
                  is_symlink = excluded.is_symlink,
                  is_package = excluded.is_package,
                  is_hidden = excluded.is_hidden,
                  device_id = excluded.device_id,
                  inode = excluded.inode,
                  scan_generation = excluded.scan_generation
                """
            )

            for entry in entries {
                try statement.bind([
                    .text(scopeID),
                    .text(entry.path),
                    .text(entry.parentPath),
                    .text(entry.name),
                    .text(entry.searchName),
                    .text(entry.searchPath),
                    .text(entry.fileExtension),
                    .text(entry.kind.rawValue),
                    .int64(entry.sizeBytes),
                    .double(entry.modifiedAt.timeIntervalSince1970),
                    .int64(entry.isDirectory ? 1 : 0),
                    .int64(entry.isSymlink ? 1 : 0),
                    .int64(entry.isPackage ? 1 : 0),
                    .int64(entry.isHidden ? 1 : 0),
                    entry.deviceID.map { .int64(Int64(bitPattern: $0)) } ?? .null,
                    entry.inode.map { .int64(Int64(bitPattern: $0)) } ?? .null,
                    .int64(generation)
                ])
                _ = try statement.step()
                try statement.reset()
            }
        }
    }

    public func delete(path: String) throws {
        let connection = try writableConnection()
        let statement = try connection.prepare(
            "DELETE FROM entries WHERE path = ? OR substr(path, 1, length(?) + 1) = ? || '/'"
        )
        try statement.bind([.text(path), .text(path), .text(path)])
        _ = try statement.step()
    }

    public func completeScopeScan(scopeID: String, generation: Int64) throws {
        let connection = try writableConnection()
        try connection.transaction {
            let prune = try connection.prepare(
                "DELETE FROM entries WHERE scope_id = ? AND scan_generation < ?"
            )
            try prune.bind([.text(scopeID), .int64(generation)])
            _ = try prune.step()

            let update = try connection.prepare(
                "UPDATE scopes SET completed_generation = ?, active_generation = NULL WHERE id = ?"
            )
            try update.bind([.int64(generation), .text(scopeID)])
            _ = try update.step()
        }
    }

    public func updateEventCheckpoint(scopeID: String, eventID: UInt64) throws {
        let connection = try writableConnection()
        let statement = try connection.prepare(
            "UPDATE scopes SET last_event_id = ? WHERE id = ?"
        )
        try statement.bind([.int64(Int64(bitPattern: eventID)), .text(scopeID)])
        _ = try statement.step()
    }

    private func writableConnection() throws -> SQLiteConnection {
        try SQLiteConnection(
            path: databaseURL.path,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        )
    }

    private static func initializeSchema(at databaseURL: URL) throws {
        let connection = try SQLiteConnection(
            path: databaseURL.path,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        )
        try connection.execute(
            """
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;
            PRAGMA user_version = 1;

            CREATE TABLE IF NOT EXISTS scopes (
              id TEXT PRIMARY KEY,
              root_path TEXT NOT NULL,
              volume_type TEXT NOT NULL,
              is_enabled INTEGER NOT NULL,
              active_generation INTEGER,
              completed_generation INTEGER NOT NULL DEFAULT 0,
              last_event_id INTEGER
            );

            CREATE TABLE IF NOT EXISTS entries (
              id INTEGER PRIMARY KEY,
              scope_id TEXT NOT NULL,
              path TEXT NOT NULL UNIQUE,
              parent_path TEXT NOT NULL,
              name TEXT NOT NULL,
              search_name TEXT NOT NULL,
              search_path TEXT NOT NULL,
              extension TEXT NOT NULL,
              kind TEXT NOT NULL,
              size_bytes INTEGER NOT NULL,
              modified_at REAL NOT NULL,
              is_directory INTEGER NOT NULL,
              is_symlink INTEGER NOT NULL,
              is_package INTEGER NOT NULL,
              is_hidden INTEGER NOT NULL,
              device_id INTEGER,
              inode INTEGER,
              scan_generation INTEGER NOT NULL,
              FOREIGN KEY(scope_id) REFERENCES scopes(id) ON DELETE CASCADE
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
              search_name,
              search_path,
              content='entries',
              content_rowid='id',
              tokenize='trigram'
            );

            CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
              INSERT INTO entries_fts(rowid, search_name, search_path)
              VALUES (new.id, new.search_name, new.search_path);
            END;
            CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
              INSERT INTO entries_fts(entries_fts, rowid, search_name, search_path)
              VALUES ('delete', old.id, old.search_name, old.search_path);
            END;
            CREATE TRIGGER IF NOT EXISTS entries_au AFTER UPDATE ON entries BEGIN
              INSERT INTO entries_fts(entries_fts, rowid, search_name, search_path)
              VALUES ('delete', old.id, old.search_name, old.search_path);
              INSERT INTO entries_fts(rowid, search_name, search_path)
              VALUES (new.id, new.search_name, new.search_path);
            END;

            CREATE INDEX IF NOT EXISTS idx_entries_scope_generation ON entries(scope_id, scan_generation);
            CREATE INDEX IF NOT EXISTS idx_entries_parent_path ON entries(parent_path);
            CREATE INDEX IF NOT EXISTS idx_entries_extension ON entries(extension);
            CREATE INDEX IF NOT EXISTS idx_entries_kind ON entries(kind);
            CREATE INDEX IF NOT EXISTS idx_entries_modified_at ON entries(modified_at DESC);
            CREATE INDEX IF NOT EXISTS idx_entries_search_name ON entries(search_name);
            """
        )
    }
}
