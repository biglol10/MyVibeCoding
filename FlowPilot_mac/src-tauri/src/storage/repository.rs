use chrono::{DateTime, Utc};
use rusqlite::types::Type;
use rusqlite::{params, Connection, OptionalExtension};
use std::io;
use std::path::Path;
use uuid::Uuid;

use crate::browser_bridge::BrowserEventDraft;
use crate::domain::activity::{ActivitySession, ActivitySource};
use crate::domain::presets::default_rules;
use crate::domain::rules::{ClassificationRule, ProductivityCategory, RuleType};
use crate::storage::schema::initialize_schema;

#[derive(Debug, PartialEq)]
pub struct BrowserEvent {
    pub id: String,
    pub occurred_at: String,
    pub domain: String,
    pub url: Option<String>,
    pub title: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActivityGroup {
    pub id: String,
    pub name: String,
    pub color: String,
    pub matchers: Vec<ActivityGroupMatcher>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActivityGroupMatcher {
    pub id: String,
    pub group_id: String,
    pub rule_type: RuleType,
    pub pattern: String,
    pub priority: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionOverride {
    pub session_id: String,
    pub category_override: Option<ProductivityCategory>,
    pub display_name_override: Option<String>,
    pub note: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DisplayNameOverride {
    pub id: String,
    pub rule_type: RuleType,
    pub pattern: String,
    pub display_name: String,
    pub priority: i64,
}

pub struct Repository {
    conn: Connection,
}

impl Repository {
    pub fn in_memory_for_test() -> rusqlite::Result<Self> {
        let conn = Connection::open_in_memory()?;
        initialize_schema(&conn)?;
        seed_builtin_rules(&conn)?;
        Ok(Self { conn })
    }

    pub fn open(path: impl AsRef<Path>) -> rusqlite::Result<Self> {
        let conn = Connection::open(path)?;
        initialize_schema(&conn)?;
        seed_builtin_rules(&conn)?;
        Ok(Self { conn })
    }

    pub fn open_default() -> rusqlite::Result<Self> {
        Self::open("time-manager.sqlite3")
    }

    pub fn save_session(&self, session: &ActivitySession) -> rusqlite::Result<()> {
        let stored_url: Option<&str> = None;

        self.conn.execute(
            r#"
            INSERT INTO activity_sessions (
              id, started_at, ended_at, duration_seconds, source, app_name, process_name,
              window_title, domain, url, url_storage_mode, is_idle, created_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 'domain', ?11, ?12)
            ON CONFLICT(id) DO UPDATE SET
              started_at = excluded.started_at,
              ended_at = excluded.ended_at,
              duration_seconds = excluded.duration_seconds,
              source = excluded.source,
              app_name = excluded.app_name,
              process_name = excluded.process_name,
              window_title = excluded.window_title,
              domain = excluded.domain,
              url = excluded.url,
              url_storage_mode = excluded.url_storage_mode,
              is_idle = excluded.is_idle
            "#,
            params![
                &session.id,
                session.started_at.to_rfc3339(),
                session.ended_at.to_rfc3339(),
                session.duration_seconds,
                activity_source_to_db(&session.source),
                &session.app_name,
                &session.process_name,
                &session.window_title,
                session.domain.as_deref(),
                stored_url,
                if session.is_idle { 1 } else { 0 },
                Utc::now().to_rfc3339(),
            ],
        )?;
        Ok(())
    }

    pub fn list_sessions_for_day(
        &self,
        date: chrono::NaiveDate,
    ) -> rusqlite::Result<Vec<ActivitySession>> {
        let start = date.and_hms_opt(0, 0, 0).unwrap().and_utc();
        let end = start + chrono::Duration::days(1);
        self.list_sessions_between(start, end)
    }

    pub fn list_sessions_between(
        &self,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> rusqlite::Result<Vec<ActivitySession>> {
        let mut stmt = self.conn.prepare(
            r#"
            SELECT id, started_at, ended_at, duration_seconds, source, app_name, process_name,
                   window_title, domain, url, is_idle
            FROM activity_sessions
            WHERE started_at >= ?1 AND started_at < ?2
            ORDER BY started_at ASC
            "#,
        )?;

        let rows = stmt.query_map(params![start.to_rfc3339(), end.to_rfc3339()], |row| {
            let started_at: String = row.get(1)?;
            let ended_at: String = row.get(2)?;
            let source: String = row.get(4)?;
            Ok(ActivitySession {
                id: row.get(0)?,
                started_at: parse_utc_rfc3339(1, &started_at)?,
                ended_at: parse_utc_rfc3339(2, &ended_at)?,
                duration_seconds: row.get(3)?,
                source: activity_source_from_db(4, &source)?,
                app_name: row.get(5)?,
                process_name: row.get(6)?,
                window_title: row.get(7)?,
                domain: row.get(8)?,
                url: row.get(9)?,
                is_idle: row.get::<_, i64>(10)? == 1,
            })
        })?;

        rows.collect()
    }

    pub fn save_browser_event(&self, draft: BrowserEventDraft) -> rusqlite::Result<()> {
        let observed_at = Utc::now();
        self.conn.execute(
            r#"
            INSERT INTO browser_events (id, occurred_at, domain, url, title)
            VALUES (?1, ?2, ?3, ?4, ?5)
            "#,
            params![
                Uuid::new_v4().to_string(),
                observed_at.to_rfc3339(),
                &draft.domain,
                draft.url.as_deref(),
                &draft.title,
            ],
        )?;
        self.save_browser_tab_observation(&draft, observed_at)?;
        Ok(())
    }

    fn save_browser_tab_observation(
        &self,
        draft: &BrowserEventDraft,
        observed_at: DateTime<Utc>,
    ) -> rusqlite::Result<()> {
        let Some(tab_id) = draft.tab_id else {
            return Ok(());
        };
        let process_name = format!("browser-tab:{tab_id}");
        let latest = self.latest_browser_tab_session(&process_name)?;
        if let Some(mut session) = latest {
            let should_extend = session.domain.as_deref() == Some(draft.domain.as_str())
                && session.window_title == draft.title;
            session.ended_at = observed_at.max(session.started_at);
            session.duration_seconds = (session.ended_at - session.started_at)
                .num_seconds()
                .max(1);
            self.save_session(&session)?;

            if should_extend {
                return Ok(());
            }
        }

        let session = ActivitySession {
            id: format!("browser-tab:{}", Uuid::new_v4()),
            started_at: observed_at,
            ended_at: observed_at,
            duration_seconds: 1,
            source: ActivitySource::BrowserExtension,
            app_name: "Chrome".into(),
            process_name,
            window_title: draft.title.clone(),
            domain: Some(draft.domain.clone()),
            url: draft.url.clone(),
            is_idle: false,
        };
        self.save_session(&session)
    }

    fn latest_browser_tab_session(
        &self,
        process_name: &str,
    ) -> rusqlite::Result<Option<ActivitySession>> {
        self.conn
            .query_row(
                r#"
                SELECT id, started_at, ended_at, duration_seconds, source, app_name, process_name,
                       window_title, domain, url, is_idle
                FROM activity_sessions
                WHERE source='browserExtension' AND process_name=?1
                ORDER BY ended_at DESC
                LIMIT 1
                "#,
                [process_name],
                |row| {
                    let started_at: String = row.get(1)?;
                    let ended_at: String = row.get(2)?;
                    let source: String = row.get(4)?;
                    Ok(ActivitySession {
                        id: row.get(0)?,
                        started_at: parse_utc_rfc3339(1, &started_at)?,
                        ended_at: parse_utc_rfc3339(2, &ended_at)?,
                        duration_seconds: row.get(3)?,
                        source: activity_source_from_db(4, &source)?,
                        app_name: row.get(5)?,
                        process_name: row.get(6)?,
                        window_title: row.get(7)?,
                        domain: row.get(8)?,
                        url: row.get(9)?,
                        is_idle: row.get::<_, i64>(10)? == 1,
                    })
                },
            )
            .optional()
    }

    pub fn list_recent_browser_events(&self, limit: i64) -> rusqlite::Result<Vec<BrowserEvent>> {
        let mut stmt = self.conn.prepare(
            r#"
            SELECT id, occurred_at, domain, url, title
            FROM browser_events
            ORDER BY occurred_at DESC
            LIMIT ?1
            "#,
        )?;

        let rows = stmt.query_map([limit], |row| {
            Ok(BrowserEvent {
                id: row.get(0)?,
                occurred_at: row.get(1)?,
                domain: row.get(2)?,
                url: row.get(3)?,
                title: row.get(4)?,
            })
        })?;

        rows.collect()
    }

    pub fn save_rule(&self, rule: &ClassificationRule) -> rusqlite::Result<()> {
        let now = Utc::now().to_rfc3339();

        self.conn.execute(
            r#"
            INSERT INTO classification_rules (
              id, name, rule_type, pattern, category, priority, is_builtin, is_enabled,
              created_at, updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name,
              rule_type = excluded.rule_type,
              pattern = excluded.pattern,
              category = excluded.category,
              priority = excluded.priority,
              is_builtin = excluded.is_builtin,
              is_enabled = excluded.is_enabled,
              updated_at = excluded.updated_at
            "#,
            params![
                &rule.id,
                &rule.name,
                rule_type_to_db(&rule.rule_type),
                &rule.pattern,
                productivity_category_to_db(&rule.category),
                rule.priority,
                bool_to_db(rule.is_builtin),
                bool_to_db(rule.is_enabled),
                &now,
                &now,
            ],
        )?;
        Ok(())
    }

    pub fn list_rules(&self) -> rusqlite::Result<Vec<ClassificationRule>> {
        let mut stmt = self.conn.prepare(
            r#"
            SELECT id, name, rule_type, pattern, category, priority, is_builtin, is_enabled
            FROM classification_rules
            ORDER BY is_builtin ASC, priority DESC, updated_at DESC, id ASC
            "#,
        )?;

        let rows = stmt.query_map([], |row| {
            let rule_type: String = row.get(2)?;
            let category: String = row.get(4)?;

            Ok(ClassificationRule {
                id: row.get(0)?,
                name: row.get(1)?,
                rule_type: rule_type_from_db(2, &rule_type)?,
                pattern: row.get(3)?,
                category: productivity_category_from_db(4, &category)?,
                priority: row.get(5)?,
                is_builtin: row.get::<_, i64>(6)? == 1,
                is_enabled: row.get::<_, i64>(7)? == 1,
            })
        })?;

        rows.collect()
    }

    pub fn save_group(&self, group: &ActivityGroup) -> rusqlite::Result<()> {
        let now = Utc::now().to_rfc3339();

        self.conn.execute(
            r#"
            INSERT INTO activity_groups (id, name, color, created_at, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name,
              color = excluded.color,
              updated_at = excluded.updated_at
            "#,
            params![&group.id, &group.name, &group.color, &now, &now],
        )?;

        self.conn.execute(
            "DELETE FROM activity_group_matchers WHERE group_id=?1",
            [&group.id],
        )?;

        for matcher in &group.matchers {
            self.conn.execute(
                r#"
                INSERT INTO activity_group_matchers (
                  id, group_id, rule_type, pattern, priority, created_at, updated_at
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                "#,
                params![
                    &matcher.id,
                    &group.id,
                    rule_type_to_db(&matcher.rule_type),
                    &matcher.pattern,
                    matcher.priority,
                    &now,
                    &now,
                ],
            )?;
        }

        Ok(())
    }

    pub fn list_groups(&self) -> rusqlite::Result<Vec<ActivityGroup>> {
        let mut stmt = self.conn.prepare(
            r#"
            SELECT id, name, color
            FROM activity_groups
            ORDER BY updated_at DESC, name ASC
            "#,
        )?;

        let rows = stmt.query_map([], |row| {
            let id: String = row.get(0)?;
            Ok(ActivityGroup {
                matchers: self.list_group_matchers(&id)?,
                id,
                name: row.get(1)?,
                color: row.get(2)?,
            })
        })?;

        rows.collect()
    }

    pub fn delete_group(&self, group_id: &str) -> rusqlite::Result<()> {
        self.conn
            .execute("DELETE FROM activity_groups WHERE id=?1", [group_id])?;
        Ok(())
    }

    pub fn upsert_session_override(&self, override_row: &SessionOverride) -> rusqlite::Result<()> {
        let now = Utc::now().to_rfc3339();
        let category = override_row
            .category_override
            .as_ref()
            .map(productivity_category_to_db);

        self.conn.execute(
            r#"
            INSERT INTO session_overrides (
              session_id, category_override, display_name_override, note, updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5)
            ON CONFLICT(session_id) DO UPDATE SET
              category_override = excluded.category_override,
              display_name_override = excluded.display_name_override,
              note = excluded.note,
              updated_at = excluded.updated_at
            "#,
            params![
                &override_row.session_id,
                category,
                override_row.display_name_override.as_deref(),
                override_row.note.as_deref(),
                &now,
            ],
        )?;
        Ok(())
    }

    pub fn get_session_override(
        &self,
        session_id: &str,
    ) -> rusqlite::Result<Option<SessionOverride>> {
        self.conn
            .query_row(
                r#"
                SELECT session_id, category_override, display_name_override, note
                FROM session_overrides
                WHERE session_id=?1
                "#,
                [session_id],
                |row| {
                    let category: Option<String> = row.get(1)?;
                    Ok(SessionOverride {
                        session_id: row.get(0)?,
                        category_override: category
                            .as_deref()
                            .map(|value| productivity_category_from_db(1, value))
                            .transpose()?,
                        display_name_override: row.get(2)?,
                        note: row.get(3)?,
                    })
                },
            )
            .optional()
    }

    pub fn delete_session_override(&self, session_id: &str) -> rusqlite::Result<()> {
        self.conn
            .execute("DELETE FROM session_overrides WHERE session_id=?1", [session_id])?;
        Ok(())
    }

    pub fn save_display_name_override(
        &self,
        override_row: &DisplayNameOverride,
    ) -> rusqlite::Result<()> {
        let now = Utc::now().to_rfc3339();

        self.conn.execute(
            r#"
            INSERT INTO display_name_overrides (
              id, rule_type, pattern, display_name, priority, created_at, updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
            ON CONFLICT(id) DO UPDATE SET
              rule_type = excluded.rule_type,
              pattern = excluded.pattern,
              display_name = excluded.display_name,
              priority = excluded.priority,
              updated_at = excluded.updated_at
            "#,
            params![
                &override_row.id,
                rule_type_to_db(&override_row.rule_type),
                &override_row.pattern,
                &override_row.display_name,
                override_row.priority,
                &now,
                &now,
            ],
        )?;
        Ok(())
    }

    pub fn list_display_name_overrides(&self) -> rusqlite::Result<Vec<DisplayNameOverride>> {
        let mut stmt = self.conn.prepare(
            r#"
            SELECT id, rule_type, pattern, display_name, priority
            FROM display_name_overrides
            ORDER BY priority DESC, updated_at DESC, id ASC
            "#,
        )?;

        let rows = stmt.query_map([], |row| {
            let rule_type: String = row.get(1)?;
            Ok(DisplayNameOverride {
                id: row.get(0)?,
                rule_type: rule_type_from_db(1, &rule_type)?,
                pattern: row.get(2)?,
                display_name: row.get(3)?,
                priority: row.get(4)?,
            })
        })?;

        rows.collect()
    }

    pub fn delete_display_name_override(&self, override_id: &str) -> rusqlite::Result<()> {
        self.conn
            .execute("DELETE FROM display_name_overrides WHERE id=?1", [override_id])?;
        Ok(())
    }

    fn list_group_matchers(&self, group_id: &str) -> rusqlite::Result<Vec<ActivityGroupMatcher>> {
        let mut stmt = self.conn.prepare(
            r#"
            SELECT id, group_id, rule_type, pattern, priority
            FROM activity_group_matchers
            WHERE group_id=?1
            ORDER BY priority DESC, updated_at DESC, id ASC
            "#,
        )?;

        let rows = stmt.query_map([group_id], |row| {
            let rule_type: String = row.get(2)?;
            Ok(ActivityGroupMatcher {
                id: row.get(0)?,
                group_id: row.get(1)?,
                rule_type: rule_type_from_db(2, &rule_type)?,
                pattern: row.get(3)?,
                priority: row.get(4)?,
            })
        })?;

        rows.collect()
    }
}

fn seed_builtin_rules(conn: &Connection) -> rusqlite::Result<()> {
    let now = Utc::now().to_rfc3339();

    for rule in default_rules() {
        conn.execute(
            r#"
            INSERT INTO classification_rules (
              id, name, rule_type, pattern, category, priority, is_builtin, is_enabled,
              created_at, updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
            ON CONFLICT(id) DO NOTHING
            "#,
            params![
                &rule.id,
                &rule.name,
                rule_type_to_db(&rule.rule_type),
                &rule.pattern,
                productivity_category_to_db(&rule.category),
                rule.priority,
                bool_to_db(rule.is_builtin),
                bool_to_db(rule.is_enabled),
                &now,
                &now,
            ],
        )?;
    }

    Ok(())
}

fn activity_source_to_db(source: &ActivitySource) -> &'static str {
    match source {
        ActivitySource::ActiveWindow => "activeWindow",
        ActivitySource::BrowserExtension => "browserExtension",
        ActivitySource::Idle => "idle",
        ActivitySource::Manual => "manual",
    }
}

fn activity_source_from_db(index: usize, value: &str) -> rusqlite::Result<ActivitySource> {
    match value {
        "activeWindow" => Ok(ActivitySource::ActiveWindow),
        "browserExtension" => Ok(ActivitySource::BrowserExtension),
        "idle" => Ok(ActivitySource::Idle),
        "manual" => Ok(ActivitySource::Manual),
        _ => Err(rusqlite::Error::FromSqlConversionFailure(
            index,
            Type::Text,
            Box::new(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("unknown activity source: {value}"),
            )),
        )),
    }
}

fn rule_type_to_db(rule_type: &RuleType) -> &'static str {
    match rule_type {
        RuleType::Domain => "domain",
        RuleType::App => "app",
        RuleType::TitleKeyword => "titleKeyword",
        RuleType::UrlPattern => "urlPattern",
    }
}

fn rule_type_from_db(index: usize, value: &str) -> rusqlite::Result<RuleType> {
    match value {
        "domain" => Ok(RuleType::Domain),
        "app" => Ok(RuleType::App),
        "titleKeyword" => Ok(RuleType::TitleKeyword),
        "urlPattern" => Ok(RuleType::UrlPattern),
        _ => Err(invalid_text_value(
            index,
            format!("unknown rule type: {value}"),
        )),
    }
}

fn productivity_category_to_db(category: &ProductivityCategory) -> &'static str {
    match category {
        ProductivityCategory::Productive => "productive",
        ProductivityCategory::Unproductive => "unproductive",
        ProductivityCategory::Neutral => "neutral",
        ProductivityCategory::Ignored => "ignored",
        ProductivityCategory::Uncategorized => "uncategorized",
    }
}

fn productivity_category_from_db(
    index: usize,
    value: &str,
) -> rusqlite::Result<ProductivityCategory> {
    match value {
        "productive" => Ok(ProductivityCategory::Productive),
        "unproductive" => Ok(ProductivityCategory::Unproductive),
        "neutral" => Ok(ProductivityCategory::Neutral),
        "ignored" => Ok(ProductivityCategory::Ignored),
        "uncategorized" => Ok(ProductivityCategory::Uncategorized),
        _ => Err(invalid_text_value(
            index,
            format!("unknown productivity category: {value}"),
        )),
    }
}

fn bool_to_db(value: bool) -> i64 {
    if value {
        1
    } else {
        0
    }
}

fn invalid_text_value(index: usize, message: String) -> rusqlite::Error {
    rusqlite::Error::FromSqlConversionFailure(
        index,
        Type::Text,
        Box::new(io::Error::new(io::ErrorKind::InvalidData, message)),
    )
}

fn parse_utc_rfc3339(index: usize, value: &str) -> rusqlite::Result<chrono::DateTime<Utc>> {
    chrono::DateTime::parse_from_rfc3339(value)
        .map(|parsed| parsed.with_timezone(&Utc))
        .map_err(|err| rusqlite::Error::FromSqlConversionFailure(index, Type::Text, Box::new(err)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::rules::{ClassificationRule, ProductivityCategory, RuleType};

    fn test_session(id: &str, started_at: chrono::DateTime<Utc>) -> ActivitySession {
        ActivitySession {
            id: id.into(),
            started_at,
            ended_at: started_at + chrono::Duration::minutes(5),
            duration_seconds: 300,
            source: ActivitySource::BrowserExtension,
            app_name: "Chrome".into(),
            process_name: "chrome.exe".into(),
            window_title: "ChatGPT".into(),
            domain: Some("chatgpt.com".into()),
            url: Some("https://chatgpt.com/c/private".into()),
            is_idle: true,
        }
    }

    #[test]
    fn saves_and_lists_sessions_for_day() {
        let repo = Repository::in_memory_for_test().expect("repo");
        let started_at = Utc::now();
        let session = test_session("session-1", started_at);

        repo.save_session(&session).expect("saved");
        let rows = repo
            .list_sessions_for_day(started_at.date_naive())
            .expect("rows");

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "session-1");
        assert_eq!(rows[0].started_at, session.started_at);
        assert_eq!(rows[0].ended_at, session.ended_at);
        assert_eq!(rows[0].duration_seconds, 300);
        assert_eq!(rows[0].source, ActivitySource::BrowserExtension);
        assert_eq!(rows[0].domain.as_deref(), Some("chatgpt.com"));
        assert_eq!(rows[0].url, None);
        assert!(rows[0].is_idle);
    }

    #[test]
    fn opens_database_at_explicit_path() {
        let path = std::env::temp_dir().join(format!(
            "time-manager-repository-{}.sqlite3",
            Uuid::new_v4()
        ));

        {
            let repo = Repository::open(&path).expect("repo opens");
            let builtin_count: i64 = repo
                .conn
                .query_row(
                    "SELECT COUNT(*) FROM classification_rules WHERE is_builtin=1",
                    [],
                    |row| row.get(0),
                )
                .expect("builtin count");

            assert!(builtin_count > 0);
        }

        assert!(path.exists());
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn updates_session_without_deleting_classification_result() {
        let repo = Repository::in_memory_for_test().expect("repo");
        let started_at = Utc::now();
        let mut session = test_session("session-2", started_at);
        repo.save_session(&session).expect("first save");
        repo.conn
            .execute(
                r#"
                INSERT INTO classification_results (
                  session_id, category, confidence, classified_at
                ) VALUES (?1, 'productive', 1.0, ?2)
                "#,
                params![&session.id, Utc::now().to_rfc3339()],
            )
            .expect("classification result");

        session.duration_seconds = 600;
        session.window_title = "Updated title".into();
        repo.save_session(&session).expect("second save");

        let classification_count: i64 = repo
            .conn
            .query_row(
                "SELECT COUNT(*) FROM classification_results WHERE session_id=?1",
                [&session.id],
                |row| row.get(0),
            )
            .expect("classification count");
        let title: String = repo
            .conn
            .query_row(
                "SELECT window_title FROM activity_sessions WHERE id=?1",
                [&session.id],
                |row| row.get(0),
            )
            .expect("session title");

        assert_eq!(classification_count, 1);
        assert_eq!(title, "Updated title");
    }

    #[test]
    fn returns_error_for_invalid_timestamps() {
        let repo = Repository::in_memory_for_test().expect("repo");
        let date = chrono::NaiveDate::from_ymd_opt(2026, 6, 18).expect("date");
        repo.conn
            .execute(
                r#"
                INSERT INTO activity_sessions (
                  id, started_at, ended_at, duration_seconds, source, app_name, process_name,
                  window_title, domain, url_storage_mode, is_idle, created_at
                ) VALUES (
                  'bad-time', '2026-06-18Tbad', 'also-bad', 1, 'activeWindow',
                  'App', 'app.exe', 'Title', NULL, 'domain', 0, '2026-01-01T00:00:00Z'
                )
                "#,
                [],
            )
            .expect("bad row");

        let error = repo
            .list_sessions_for_day(date)
            .expect_err("invalid timestamp should return an error");

        assert!(matches!(
            error,
            rusqlite::Error::FromSqlConversionFailure(_, _, _)
        ));
    }

    #[test]
    fn saves_custom_rule_and_lists_it_before_builtin_rules() {
        let repo = Repository::in_memory_for_test().expect("repo");
        let custom = ClassificationRule {
            id: "user:domain:youtube.com".into(),
            name: "YouTube learning".into(),
            rule_type: RuleType::Domain,
            pattern: "youtube.com".into(),
            category: ProductivityCategory::Productive,
            priority: 10,
            is_builtin: false,
            is_enabled: true,
        };

        repo.save_rule(&custom).expect("rule saved");

        let rules = repo.list_rules().expect("rules listed");

        assert!(rules.len() > 1, "builtin rules should be included");
        assert_eq!(rules[0], custom);
        assert!(
            rules
                .iter()
                .skip(1)
                .any(|rule| rule.id == "builtin:domain:chatgpt.com"),
            "expected built-in ChatGPT rule after custom rules"
        );
    }

    #[test]
    fn repository_initialization_persists_builtin_rules_for_classification_results() {
        let repo = Repository::in_memory_for_test().expect("repo");
        let started_at = Utc::now();
        let session = test_session("builtin-classified", started_at);
        repo.save_session(&session).expect("session saved");

        let builtin_count: i64 = repo
            .conn
            .query_row(
                "SELECT COUNT(*) FROM classification_rules WHERE id='builtin:domain:chatgpt.com'",
                [],
                |row| row.get(0),
            )
            .expect("builtin count");
        assert_eq!(builtin_count, 1);

        repo.conn
            .execute(
                r#"
                INSERT INTO classification_results (
                  session_id, rule_id, category, confidence, classified_at
                ) VALUES (?1, 'builtin:domain:chatgpt.com', 'productive', 1.0, ?2)
                "#,
                params![&session.id, Utc::now().to_rfc3339()],
            )
            .expect("classification result can reference builtin rule");
    }

    #[test]
    fn seeding_builtin_rules_preserves_existing_rows() {
        let repo = Repository::in_memory_for_test().expect("repo");

        repo.conn
            .execute(
                r#"
                UPDATE classification_rules
                SET name='Edited ChatGPT', category='neutral', priority=42
                WHERE id='builtin:domain:chatgpt.com'
                "#,
                [],
            )
            .expect("edited builtin");

        seed_builtin_rules(&repo.conn).expect("reseeding succeeds");

        let edited: (String, String, i32) = repo
            .conn
            .query_row(
                "SELECT name, category, priority FROM classification_rules WHERE id='builtin:domain:chatgpt.com'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .expect("edited builtin row");

        assert_eq!(edited, ("Edited ChatGPT".into(), "neutral".into(), 42));
    }

    #[test]
    fn saves_domain_without_full_url_by_default() {
        let repo = Repository::in_memory_for_test().expect("repo");
        repo.save_browser_event(BrowserEventDraft {
            domain: "youtube.com".into(),
            tab_id: None,
            url: None,
            title: "YouTube".into(),
        })
        .expect("saved");

        let events = repo.list_recent_browser_events(10).expect("events");

        assert_eq!(events[0].domain, "youtube.com");
        assert_eq!(events[0].url, None);
    }

    #[test]
    fn browser_tab_observations_extend_activity_sessions_by_domain() {
        let repo = Repository::in_memory_for_test().expect("repo");
        let start = Utc::now();

        repo.save_browser_tab_observation(
            &BrowserEventDraft {
                domain: "youtube.com".into(),
                tab_id: Some(7),
                url: None,
                title: "YouTube".into(),
            },
            start,
        )
        .expect("first observation");
        repo.save_browser_tab_observation(
            &BrowserEventDraft {
                domain: "youtube.com".into(),
                tab_id: Some(7),
                url: None,
                title: "YouTube".into(),
            },
            start + chrono::Duration::seconds(65),
        )
        .expect("second observation");

        let rows = repo
            .list_sessions_between(start - chrono::Duration::seconds(1), start + chrono::Duration::minutes(2))
            .expect("sessions");

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].source, ActivitySource::BrowserExtension);
        assert_eq!(rows[0].domain.as_deref(), Some("youtube.com"));
        assert_eq!(rows[0].process_name, "browser-tab:7");
        assert_eq!(rows[0].duration_seconds, 65);
    }

    #[test]
    fn browser_tab_navigation_starts_a_new_domain_session() {
        let repo = Repository::in_memory_for_test().expect("repo");
        let start = Utc::now();

        repo.save_browser_tab_observation(
            &BrowserEventDraft {
                domain: "youtube.com".into(),
                tab_id: Some(7),
                url: None,
                title: "YouTube".into(),
            },
            start,
        )
        .expect("youtube observation");
        repo.save_browser_tab_observation(
            &BrowserEventDraft {
                domain: "naver.com".into(),
                tab_id: Some(7),
                url: None,
                title: "Naver".into(),
            },
            start + chrono::Duration::seconds(30),
        )
        .expect("naver observation");

        let rows = repo
            .list_sessions_between(start - chrono::Duration::seconds(1), start + chrono::Duration::minutes(1))
            .expect("sessions");

        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].domain.as_deref(), Some("youtube.com"));
        assert_eq!(rows[0].duration_seconds, 30);
        assert_eq!(rows[1].domain.as_deref(), Some("naver.com"));
        assert_eq!(rows[1].duration_seconds, 1);
    }
}
