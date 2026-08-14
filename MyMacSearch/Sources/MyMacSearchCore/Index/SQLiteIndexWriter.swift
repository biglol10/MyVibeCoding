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

    public func updateScopeScanStatistics(
        scopeID: String,
        skippedCount: Int,
        permissionDeniedCount: Int
    ) async throws {
        let connection = try writableConnection()
        let statement = try connection.prepare(
            """
            UPDATE scopes
            SET last_skipped_count = ?, last_permission_denied_count = ?
            WHERE id = ?
            """
        )
        try statement.bind([
            .int64(Int64(max(skippedCount, 0))),
            .int64(Int64(max(permissionDeniedCount, 0))),
            .text(scopeID)
        ])
        _ = try statement.step()
    }

    public func completeScopeScan(scopeID: String, generation: Int64, completedAt: Date) throws {
        let connection = try writableConnection()
        try connection.transaction {
            let prune = try connection.prepare(
                "DELETE FROM entries WHERE scope_id = ? AND scan_generation < ?"
            )
            try prune.bind([.text(scopeID), .int64(generation)])
            _ = try prune.step()

            let update = try connection.prepare(
                "UPDATE scopes SET completed_generation = ?, active_generation = NULL, last_completed_scan_at = ?, last_error = NULL WHERE id = ?"
            )
            try update.bind([.int64(generation), .double(completedAt.timeIntervalSince1970), .text(scopeID)])
            _ = try update.step()
        }
    }

    public func updateEventCheckpoint(scopeID: String, eventID: UInt64, occurredAt: Date) throws {
        let connection = try writableConnection()
        let statement = try connection.prepare(
            "UPDATE scopes SET last_event_id = ?, last_event_at = ? WHERE id = ?"
        )
        try statement.bind([
            .int64(Int64(bitPattern: eventID)),
            .double(occurredAt.timeIntervalSince1970),
            .text(scopeID)
        ])
        _ = try statement.step()
    }

    public func recordIssue(
        scopeID: String,
        path: String,
        category: IndexIssueCategory,
        message: String,
        occurredAt: Date
    ) throws {
        let connection = try writableConnection()
        try connection.transaction {
            let issue = try connection.prepare(
                """
                INSERT INTO index_issues(
                  scope_id, path, category, message, first_seen_at, last_seen_at, occurrence_count, resolved_at
                ) VALUES (?, ?, ?, ?, ?, ?, 1, NULL)
                ON CONFLICT(scope_id, path, category) DO UPDATE SET
                  message = excluded.message,
                  last_seen_at = excluded.last_seen_at,
                  occurrence_count = index_issues.occurrence_count + 1,
                  resolved_at = NULL
                """
            )
            try issue.bind([
                .text(scopeID),
                .text(path),
                .text(category.rawValue),
                .text(message),
                .double(occurredAt.timeIntervalSince1970),
                .double(occurredAt.timeIntervalSince1970)
            ])
            _ = try issue.step()

            let scope = try connection.prepare("UPDATE scopes SET last_error = ? WHERE id = ?")
            try scope.bind([.text(message), .text(scopeID)])
            _ = try scope.step()
        }
    }

    public func resolveIssues(scopeID: String, resolvedAt: Date) throws {
        let connection = try writableConnection()
        let statement = try connection.prepare(
            "UPDATE index_issues SET resolved_at = ? WHERE scope_id = ? AND resolved_at IS NULL"
        )
        try statement.bind([.double(resolvedAt.timeIntervalSince1970), .text(scopeID)])
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
        try connection.execute("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;")
        let versionStatement = try connection.prepare("PRAGMA user_version")
        guard try versionStatement.step() == SQLITE_ROW else {
            throw SQLiteIndexError.invalidData("Missing schema version")
        }
        let version = versionStatement.int64(at: 0)
        let hadScopeEntryCounts = try tableExists("scope_entry_counts", connection: connection)
        guard version <= 2 else {
            throw SQLiteIndexError.invalidData("Index schema version \(version) is newer than this app supports")
        }

        if version == 1 {
            try connection.transaction {
                try connection.execute(
                    """
                    ALTER TABLE scopes ADD COLUMN last_completed_scan_at REAL;
                    ALTER TABLE scopes ADD COLUMN last_event_at REAL;
                    ALTER TABLE scopes ADD COLUMN last_error TEXT;
                    ALTER TABLE scopes ADD COLUMN last_skipped_count INTEGER NOT NULL DEFAULT 0;
                    ALTER TABLE scopes ADD COLUMN last_permission_denied_count INTEGER NOT NULL DEFAULT 0;

                    CREATE TABLE index_issues (
                      id INTEGER PRIMARY KEY,
                      scope_id TEXT NOT NULL,
                      path TEXT NOT NULL,
                      category TEXT NOT NULL,
                      message TEXT NOT NULL,
                      first_seen_at REAL NOT NULL,
                      last_seen_at REAL NOT NULL,
                      occurrence_count INTEGER NOT NULL DEFAULT 1,
                      resolved_at REAL,
                      UNIQUE(scope_id, path, category)
                    );
                    CREATE INDEX idx_index_issues_unresolved
                      ON index_issues(scope_id, resolved_at, last_seen_at DESC);
                    CREATE INDEX idx_entries_name_sort ON entries(search_name, id);
                    CREATE INDEX idx_entries_path_sort ON entries(search_path, id);
                    CREATE INDEX idx_entries_modified_sort ON entries(modified_at, id);
                    CREATE INDEX idx_entries_size_sort ON entries(size_bytes, id);
                    CREATE INDEX idx_entries_kind_name_sort ON entries(kind, search_name, id);
                    CREATE TABLE scope_entry_counts (
                      scope_id TEXT PRIMARY KEY,
                      entry_count INTEGER NOT NULL DEFAULT 0 CHECK(entry_count >= 0),
                      FOREIGN KEY(scope_id) REFERENCES scopes(id) ON DELETE CASCADE
                    );
                    INSERT INTO scope_entry_counts(scope_id, entry_count)
                      SELECT scope_id, COUNT(*) FROM entries GROUP BY scope_id;
                    \(scopeEntryCountTriggers)
                    PRAGMA user_version = 2;
                    """
                )
            }
            return
        }

        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS scopes (
              id TEXT PRIMARY KEY,
              root_path TEXT NOT NULL,
              volume_type TEXT NOT NULL,
              is_enabled INTEGER NOT NULL,
              active_generation INTEGER,
              completed_generation INTEGER NOT NULL DEFAULT 0,
              last_event_id INTEGER,
              last_completed_scan_at REAL,
              last_event_at REAL,
              last_error TEXT,
              last_skipped_count INTEGER NOT NULL DEFAULT 0,
              last_permission_denied_count INTEGER NOT NULL DEFAULT 0
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

            CREATE TABLE IF NOT EXISTS scope_entry_counts (
              scope_id TEXT PRIMARY KEY,
              entry_count INTEGER NOT NULL DEFAULT 0 CHECK(entry_count >= 0),
              FOREIGN KEY(scope_id) REFERENCES scopes(id) ON DELETE CASCADE
            );
            \(scopeEntryCountTriggers)

            CREATE INDEX IF NOT EXISTS idx_entries_scope_generation ON entries(scope_id, scan_generation);
            CREATE INDEX IF NOT EXISTS idx_entries_parent_path ON entries(parent_path);
            CREATE INDEX IF NOT EXISTS idx_entries_extension ON entries(extension);
            CREATE INDEX IF NOT EXISTS idx_entries_kind ON entries(kind);
            CREATE INDEX IF NOT EXISTS idx_entries_modified_at ON entries(modified_at DESC);
            CREATE INDEX IF NOT EXISTS idx_entries_search_name ON entries(search_name);
            CREATE INDEX IF NOT EXISTS idx_entries_name_sort ON entries(search_name, id);
            CREATE INDEX IF NOT EXISTS idx_entries_path_sort ON entries(search_path, id);
            CREATE INDEX IF NOT EXISTS idx_entries_modified_sort ON entries(modified_at, id);
            CREATE INDEX IF NOT EXISTS idx_entries_size_sort ON entries(size_bytes, id);
            CREATE INDEX IF NOT EXISTS idx_entries_kind_name_sort ON entries(kind, search_name, id);

            CREATE TABLE IF NOT EXISTS index_issues (
              id INTEGER PRIMARY KEY,
              scope_id TEXT NOT NULL,
              path TEXT NOT NULL,
              category TEXT NOT NULL,
              message TEXT NOT NULL,
              first_seen_at REAL NOT NULL,
              last_seen_at REAL NOT NULL,
              occurrence_count INTEGER NOT NULL DEFAULT 1,
              resolved_at REAL,
              UNIQUE(scope_id, path, category)
            );
            CREATE INDEX IF NOT EXISTS idx_index_issues_unresolved
              ON index_issues(scope_id, resolved_at, last_seen_at DESC);
            PRAGMA user_version = 2;
            """
        )
        if !hadScopeEntryCounts {
            try connection.execute(
                """
                INSERT OR REPLACE INTO scope_entry_counts(scope_id, entry_count)
                  SELECT scope_id, COUNT(*) FROM entries GROUP BY scope_id;
                """
            )
        }
        if try !columnExists("last_skipped_count", in: "scopes", connection: connection) {
            try connection.execute(
                "ALTER TABLE scopes ADD COLUMN last_skipped_count INTEGER NOT NULL DEFAULT 0"
            )
        }
        if try !columnExists("last_permission_denied_count", in: "scopes", connection: connection) {
            try connection.execute(
                "ALTER TABLE scopes ADD COLUMN last_permission_denied_count INTEGER NOT NULL DEFAULT 0"
            )
        }
    }

    private static let scopeEntryCountTriggers = """
        CREATE TRIGGER IF NOT EXISTS entries_count_ai AFTER INSERT ON entries BEGIN
          INSERT OR IGNORE INTO scope_entry_counts(scope_id, entry_count) VALUES(new.scope_id, 0);
          UPDATE scope_entry_counts SET entry_count = entry_count + 1 WHERE scope_id = new.scope_id;
        END;
        CREATE TRIGGER IF NOT EXISTS entries_count_ad AFTER DELETE ON entries BEGIN
          UPDATE scope_entry_counts
          SET entry_count = MAX(entry_count - 1, 0)
          WHERE scope_id = old.scope_id;
        END;
        CREATE TRIGGER IF NOT EXISTS entries_count_au AFTER UPDATE OF scope_id ON entries
        WHEN old.scope_id <> new.scope_id BEGIN
          UPDATE scope_entry_counts
          SET entry_count = MAX(entry_count - 1, 0)
          WHERE scope_id = old.scope_id;
          INSERT OR IGNORE INTO scope_entry_counts(scope_id, entry_count) VALUES(new.scope_id, 0);
          UPDATE scope_entry_counts SET entry_count = entry_count + 1 WHERE scope_id = new.scope_id;
        END;
        """

    private static func tableExists(_ name: String, connection: SQLiteConnection) throws -> Bool {
        let statement = try connection.prepare(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
        )
        try statement.bind([.text(name)])
        return try statement.step() == SQLITE_ROW
    }

    private static func columnExists(
        _ column: String,
        in table: String,
        connection: SQLiteConnection
    ) throws -> Bool {
        let statement = try connection.prepare("PRAGMA table_info(\(table))")
        while try statement.step() == SQLITE_ROW {
            if try statement.text(at: 1) == column { return true }
        }
        return false
    }
}
