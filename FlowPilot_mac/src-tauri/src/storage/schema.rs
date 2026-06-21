use rusqlite::Connection;

pub fn initialize_schema(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        r#"
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS activity_sessions (
          id TEXT PRIMARY KEY,
          started_at TEXT NOT NULL,
          ended_at TEXT NOT NULL,
          duration_seconds INTEGER NOT NULL,
          source TEXT NOT NULL,
          app_name TEXT NOT NULL,
          process_name TEXT NOT NULL,
          window_title TEXT NOT NULL,
          domain TEXT,
          url TEXT,
          url_storage_mode TEXT NOT NULL DEFAULT 'domain',
          is_idle INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS classification_rules (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          rule_type TEXT NOT NULL,
          pattern TEXT NOT NULL,
          category TEXT NOT NULL,
          priority INTEGER NOT NULL DEFAULT 0,
          is_builtin INTEGER NOT NULL DEFAULT 0,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS classification_results (
          session_id TEXT PRIMARY KEY,
          rule_id TEXT,
          category TEXT NOT NULL,
          confidence REAL NOT NULL DEFAULT 1.0,
          classified_at TEXT NOT NULL,
          FOREIGN KEY(session_id) REFERENCES activity_sessions(id) ON DELETE CASCADE,
          FOREIGN KEY(rule_id) REFERENCES classification_rules(id) ON DELETE SET NULL
        );

        CREATE TABLE IF NOT EXISTS activity_groups (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          color TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS activity_group_matchers (
          id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          rule_type TEXT NOT NULL,
          pattern TEXT NOT NULL,
          priority INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY(group_id) REFERENCES activity_groups(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS session_overrides (
          session_id TEXT PRIMARY KEY,
          category_override TEXT,
          display_name_override TEXT,
          note TEXT,
          updated_at TEXT NOT NULL,
          FOREIGN KEY(session_id) REFERENCES activity_sessions(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS display_name_overrides (
          id TEXT PRIMARY KEY,
          rule_type TEXT NOT NULL,
          pattern TEXT NOT NULL,
          display_name TEXT NOT NULL,
          priority INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS browser_events (
          id TEXT PRIMARY KEY,
          occurred_at TEXT NOT NULL,
          domain TEXT NOT NULL,
          url TEXT,
          title TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON activity_sessions(started_at);
        CREATE INDEX IF NOT EXISTS idx_sessions_domain ON activity_sessions(domain);
        CREATE INDEX IF NOT EXISTS idx_rules_type_pattern ON classification_rules(rule_type, pattern);
        CREATE INDEX IF NOT EXISTS idx_group_matchers_group_id ON activity_group_matchers(group_id);
        CREATE INDEX IF NOT EXISTS idx_display_name_overrides_type_pattern ON display_name_overrides(rule_type, pattern);
        CREATE INDEX IF NOT EXISTS idx_browser_events_occurred_at ON browser_events(occurred_at);
        CREATE INDEX IF NOT EXISTS idx_browser_events_domain ON browser_events(domain);
        "#,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn creates_activity_sessions_table() {
        let conn = Connection::open_in_memory().expect("in-memory db");
        initialize_schema(&conn).expect("schema initialized");

        let exists: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='activity_sessions'",
                [],
                |row| row.get(0),
            )
            .expect("table count");

        assert_eq!(exists, 1);
    }

    #[test]
    fn creates_browser_event_indexes() {
        let conn = Connection::open_in_memory().expect("in-memory db");
        initialize_schema(&conn).expect("schema initialized");

        for index_name in [
            "idx_browser_events_occurred_at",
            "idx_browser_events_domain",
        ] {
            let exists: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name=?1",
                    [index_name],
                    |row| row.get(0),
                )
                .expect("index count");

            assert_eq!(exists, 1, "{index_name} should exist");
        }
    }

    #[test]
    fn creates_report_overlay_tables() {
        let conn = Connection::open_in_memory().expect("in-memory db");
        initialize_schema(&conn).expect("schema initialized");

        for table_name in [
            "activity_groups",
            "activity_group_matchers",
            "display_name_overrides",
            "session_overrides",
        ] {
            let exists: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?1",
                    [table_name],
                    |row| row.get(0),
                )
                .expect("table count");

            assert_eq!(exists, 1, "{table_name} should exist");
        }
    }
}
