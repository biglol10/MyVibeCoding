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

        CREATE TABLE IF NOT EXISTS window_observations (
          id TEXT PRIMARY KEY,
          session_id TEXT,
          observed_at TEXT NOT NULL,
          app_name TEXT NOT NULL,
          process_name TEXT NOT NULL,
          pid INTEGER,
          bundle_identifier TEXT,
          window_title TEXT,
          is_visible INTEGER NOT NULL DEFAULT 0,
          is_frontmost INTEGER NOT NULL DEFAULT 0,
          is_primary INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY(session_id) REFERENCES activity_sessions(id) ON DELETE SET NULL
        );

        CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON activity_sessions(started_at);
        CREATE INDEX IF NOT EXISTS idx_sessions_domain ON activity_sessions(domain);
        CREATE INDEX IF NOT EXISTS idx_rules_type_pattern ON classification_rules(rule_type, pattern);
        CREATE INDEX IF NOT EXISTS idx_browser_events_occurred_at ON browser_events(occurred_at);
        CREATE INDEX IF NOT EXISTS idx_browser_events_domain ON browser_events(domain);
        CREATE INDEX IF NOT EXISTS idx_window_observations_observed_at ON window_observations(observed_at);
        CREATE INDEX IF NOT EXISTS idx_window_observations_session_id ON window_observations(session_id);
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
    fn creates_window_observation_table_and_indexes() {
        let conn = Connection::open_in_memory().expect("in-memory db");
        initialize_schema(&conn).expect("schema initialized");

        let table_exists: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='window_observations'",
                [],
                |row| row.get(0),
            )
            .expect("table count");

        assert_eq!(table_exists, 1);

        for index_name in [
            "idx_window_observations_observed_at",
            "idx_window_observations_session_id",
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
}
