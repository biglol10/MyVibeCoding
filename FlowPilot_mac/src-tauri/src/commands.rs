use chrono::{DateTime, Local, NaiveDate, TimeZone, Utc};
use serde::{Deserialize, Serialize};
use tauri::State;

use crate::app_state::AppState;
use crate::domain::activity::ActivitySession;
use crate::domain::classifier::classify;
use crate::domain::rules::{
    canonical_rule_pattern, ClassificationRule, ProductivityCategory, RuleType,
};
use crate::storage::repository::Repository;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TodaySummaryDto {
    pub tracked_seconds: i64,
    pub productive_seconds: i64,
    pub unproductive_seconds: i64,
    pub neutral_seconds: i64,
    pub idle_seconds: i64,
    pub uncategorized_seconds: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivitySessionDto {
    pub id: String,
    pub started_at: DateTime<Utc>,
    pub ended_at: DateTime<Utc>,
    pub duration_seconds: i64,
    pub app_name: String,
    pub process_name: String,
    pub window_title: String,
    pub domain: Option<String>,
    pub is_idle: bool,
    pub category: ProductivityCategory,
    pub matched_rule_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuleDraftDto {
    pub name: String,
    pub rule_type: RuleType,
    pub pattern: String,
    pub category: ProductivityCategory,
}

#[tauri::command]
pub fn get_today_summary(state: State<AppState>) -> Result<TodaySummaryDto, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;

    today_summary_from_repository(&repository)
}

pub(crate) fn today_summary_from_repository(
    repository: &Repository,
) -> Result<TodaySummaryDto, String> {
    let sessions = classified_sessions_for_local_today(repository)?;

    Ok(summarize_sessions(&sessions))
}

#[tauri::command]
pub fn get_today_sessions(state: State<AppState>) -> Result<Vec<ActivitySessionDto>, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;

    classified_sessions_for_local_today(&repository)
}

#[tauri::command]
pub fn get_week_sessions(state: State<AppState>) -> Result<Vec<ActivitySessionDto>, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;

    classified_sessions_for_local_week(&repository)
}

#[tauri::command]
pub fn export_today_csv(state: State<AppState>) -> Result<String, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;
    let sessions = raw_sessions_for_local_today(&repository)?;

    Ok(crate::export::sessions_to_csv(&sessions))
}

#[tauri::command]
pub fn pause_tracking(state: State<AppState>, minutes: i64) -> Result<(), String> {
    let mut status = state
        .tracking_status
        .lock()
        .map_err(|_| "Tracking status lock poisoned.".to_string())?;
    status.paused_until = Some(pause_until_for_minutes(minutes)?);
    Ok(())
}

#[tauri::command]
pub fn resume_tracking(state: State<AppState>) -> Result<(), String> {
    let mut status = state
        .tracking_status
        .lock()
        .map_err(|_| "Tracking status lock poisoned.".to_string())?;
    status.paused_until = None;
    Ok(())
}

fn pause_until_for_minutes(minutes: i64) -> Result<chrono::DateTime<chrono::Utc>, String> {
    if minutes <= 0 {
        return Err("Pause duration must be positive.".into());
    }

    Ok(chrono::Utc::now() + chrono::Duration::minutes(minutes))
}

#[tauri::command]
pub fn list_rules(state: State<AppState>) -> Result<Vec<ClassificationRule>, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;

    repository.list_rules().map_err(|error| error.to_string())
}

#[tauri::command]
pub fn create_rule(
    state: State<AppState>,
    draft: RuleDraftDto,
) -> Result<ClassificationRule, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;

    create_rule_from_draft(&repository, draft)
}

#[tauri::command]
pub fn update_rule(
    state: State<AppState>,
    rule_id: String,
    draft: RuleDraftDto,
) -> Result<ClassificationRule, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;

    update_rule_from_draft(&repository, &rule_id, draft)
}

fn create_rule_from_draft(
    repository: &Repository,
    draft: RuleDraftDto,
) -> Result<ClassificationRule, String> {
    if draft.category == ProductivityCategory::Uncategorized {
        return Err("Uncategorized cannot be used for a rule category.".into());
    }

    let pattern = canonical_rule_pattern(draft.rule_type, &draft.pattern)
        .ok_or_else(|| "Rule pattern cannot be blank.".to_string())?;
    let name = match draft.name.trim() {
        "" => pattern.clone(),
        trimmed => trimmed.to_string(),
    };
    let rule = ClassificationRule {
        id: format!(
            "user:{}:{}",
            rule_type_id_segment(&draft.rule_type),
            pattern_id_segment(&pattern)
        ),
        name,
        rule_type: draft.rule_type,
        pattern,
        category: draft.category,
        priority: 100,
        is_builtin: false,
        is_enabled: true,
    };

    repository
        .save_rule(&rule)
        .map_err(|error| error.to_string())?;

    Ok(rule)
}

fn update_rule_from_draft(
    repository: &Repository,
    rule_id: &str,
    draft: RuleDraftDto,
) -> Result<ClassificationRule, String> {
    if draft.category == ProductivityCategory::Uncategorized {
        return Err("Uncategorized cannot be used for a rule category.".into());
    }

    let existing_rule = repository
        .list_rules()
        .map_err(|error| error.to_string())?
        .into_iter()
        .find(|rule| rule.id == rule_id)
        .ok_or_else(|| "Rule not found.".to_string())?;
    let pattern = canonical_rule_pattern(draft.rule_type, &draft.pattern)
        .ok_or_else(|| "Rule pattern cannot be blank.".to_string())?;
    let name = match draft.name.trim() {
        "" => pattern.clone(),
        trimmed => trimmed.to_string(),
    };
    let rule = ClassificationRule {
        id: existing_rule.id,
        name,
        rule_type: draft.rule_type,
        pattern,
        category: draft.category,
        priority: existing_rule.priority,
        is_builtin: existing_rule.is_builtin,
        is_enabled: existing_rule.is_enabled,
    };

    repository
        .save_rule(&rule)
        .map_err(|error| error.to_string())?;

    Ok(rule)
}

fn classified_sessions_for_local_today(
    repository: &Repository,
) -> Result<Vec<ActivitySessionDto>, String> {
    let (start, end) = local_day_bounds_utc(Local::now().date_naive())?;
    classified_sessions_for_range(repository, start, end)
}

fn classified_sessions_for_local_week(
    repository: &Repository,
) -> Result<Vec<ActivitySessionDto>, String> {
    let today = Local::now().date_naive();
    let (start, _) = local_day_bounds_utc(today - chrono::Duration::days(6))?;
    let (_, end) = local_day_bounds_utc(today)?;
    classified_sessions_for_range(repository, start, end)
}

fn classified_sessions_for_range(
    repository: &Repository,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
) -> Result<Vec<ActivitySessionDto>, String> {
    let sessions = repository
        .list_sessions_between(start, end)
        .map_err(|error| error.to_string())?;
    let rules = repository.list_rules().map_err(|error| error.to_string())?;
    let (user_rules, builtin_rules): (Vec<_>, Vec<_>) =
        rules.into_iter().partition(|rule| !rule.is_builtin);

    Ok(sessions
        .into_iter()
        .map(|session| {
            let classification = classify(&session, &user_rules, &builtin_rules);
            ActivitySessionDto::from_session(
                session,
                classification.category,
                classification.matched_rule_id,
            )
        })
        .filter(|session| session.category != ProductivityCategory::Ignored)
        .collect())
}

fn raw_sessions_for_local_today(repository: &Repository) -> Result<Vec<ActivitySession>, String> {
    let (start, end) = local_day_bounds_utc(Local::now().date_naive())?;
    repository
        .list_sessions_between(start, end)
        .map_err(|error| error.to_string())
}

fn local_day_bounds_utc(date: NaiveDate) -> Result<(DateTime<Utc>, DateTime<Utc>), String> {
    let start_naive = date
        .and_hms_opt(0, 0, 0)
        .ok_or_else(|| "Unable to resolve local day start.".to_string())?;
    let end_naive = date
        .succ_opt()
        .and_then(|next_day| next_day.and_hms_opt(0, 0, 0))
        .ok_or_else(|| "Unable to resolve local day end.".to_string())?;
    let start = Local
        .from_local_datetime(&start_naive)
        .earliest()
        .ok_or_else(|| "Unable to resolve local day start.".to_string())?;
    let end = Local
        .from_local_datetime(&end_naive)
        .earliest()
        .ok_or_else(|| "Unable to resolve local day end.".to_string())?;

    Ok((start.with_timezone(&Utc), end.with_timezone(&Utc)))
}

fn summarize_sessions(sessions: &[ActivitySessionDto]) -> TodaySummaryDto {
    let mut summary = TodaySummaryDto {
        tracked_seconds: 0,
        productive_seconds: 0,
        unproductive_seconds: 0,
        neutral_seconds: 0,
        idle_seconds: 0,
        uncategorized_seconds: 0,
    };

    for session in sessions {
        if session.category == ProductivityCategory::Ignored {
            continue;
        }

        summary.tracked_seconds += session.duration_seconds;

        if session.is_idle {
            summary.idle_seconds += session.duration_seconds;
            continue;
        }

        match session.category {
            ProductivityCategory::Productive => {
                summary.productive_seconds += session.duration_seconds
            }
            ProductivityCategory::Unproductive => {
                summary.unproductive_seconds += session.duration_seconds
            }
            ProductivityCategory::Neutral => summary.neutral_seconds += session.duration_seconds,
            ProductivityCategory::Uncategorized => {
                summary.uncategorized_seconds += session.duration_seconds
            }
            ProductivityCategory::Ignored => {}
        }
    }

    summary
}

impl ActivitySessionDto {
    fn from_session(
        session: ActivitySession,
        category: ProductivityCategory,
        matched_rule_id: Option<String>,
    ) -> Self {
        Self {
            id: session.id,
            started_at: session.started_at,
            ended_at: session.ended_at,
            duration_seconds: session.duration_seconds,
            app_name: session.app_name,
            process_name: session.process_name,
            window_title: session.window_title,
            domain: session.domain,
            is_idle: session.is_idle,
            category,
            matched_rule_id,
        }
    }
}

fn rule_type_id_segment(rule_type: &RuleType) -> &'static str {
    match rule_type {
        RuleType::Domain => "domain",
        RuleType::App => "app",
        RuleType::TitleKeyword => "titleKeyword",
        RuleType::UrlPattern => "urlPattern",
    }
}

fn pattern_id_segment(pattern: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789ABCDEF";

    let mut segment = String::with_capacity(pattern.len());
    for byte in pattern.as_bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'.' | b'_' | b'-' | b'~' => {
                segment.push(*byte as char)
            }
            _ => {
                segment.push('%');
                segment.push(HEX[(byte >> 4) as usize] as char);
                segment.push(HEX[(byte & 0x0f) as usize] as char);
            }
        }
    }

    segment
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::activity::{ActivitySession, ActivitySource};
    use crate::storage::repository::Repository;
    use chrono::Duration;

    fn draft(pattern: &str, category: ProductivityCategory) -> RuleDraftDto {
        RuleDraftDto {
            name: "".into(),
            rule_type: RuleType::Domain,
            pattern: pattern.into(),
            category,
        }
    }

    fn typed_draft(
        rule_type: RuleType,
        pattern: &str,
        category: ProductivityCategory,
    ) -> RuleDraftDto {
        RuleDraftDto {
            name: "".into(),
            rule_type,
            pattern: pattern.into(),
            category,
        }
    }

    fn activity_session(
        id: &str,
        started_at: DateTime<Utc>,
        duration_seconds: i64,
        domain: Option<&str>,
        app_name: &str,
        process_name: &str,
        window_title: &str,
        is_idle: bool,
    ) -> ActivitySession {
        ActivitySession {
            id: id.into(),
            started_at,
            ended_at: started_at + Duration::seconds(duration_seconds),
            duration_seconds,
            source: if is_idle {
                ActivitySource::Idle
            } else {
                ActivitySource::BrowserExtension
            },
            app_name: app_name.into(),
            process_name: process_name.into(),
            window_title: window_title.into(),
            domain: domain.map(str::to_string),
            url: None,
            is_idle,
        }
    }

    #[test]
    fn rejects_non_positive_pause_minutes() {
        let error = pause_until_for_minutes(0).expect_err("zero minutes should be rejected");

        assert!(error.contains("positive"));
    }

    #[test]
    fn creates_domain_rules_with_canonical_pattern_and_deterministic_id() {
        let repository = Repository::in_memory_for_test().expect("repo");

        let created = create_rule_from_draft(
            &repository,
            draft(" WWW.YouTube.COM. ", ProductivityCategory::Unproductive),
        )
        .expect("created rule");
        let replaced = create_rule_from_draft(
            &repository,
            draft("youtube.com.", ProductivityCategory::Productive),
        )
        .expect("replaced rule");

        assert_eq!(created.id, "user:domain:youtube.com");
        assert_eq!(created.pattern, "youtube.com");
        assert_eq!(replaced.id, created.id);
        assert_eq!(replaced.pattern, "youtube.com");
        assert_eq!(replaced.category, ProductivityCategory::Productive);

        let user_youtube_rules = repository
            .list_rules()
            .expect("rules")
            .into_iter()
            .filter(|rule| rule.id == "user:domain:youtube.com")
            .count();
        assert_eq!(user_youtube_rules, 1);
    }

    #[test]
    fn updates_existing_rules_in_place() {
        let repository = Repository::in_memory_for_test().expect("repo");
        let original = ClassificationRule {
            id: "builtin:domain:chatgpt.com".into(),
            name: "ChatGPT".into(),
            rule_type: RuleType::Domain,
            pattern: "chatgpt.com".into(),
            category: ProductivityCategory::Productive,
            priority: 0,
            is_builtin: true,
            is_enabled: true,
        };
        repository.save_rule(&original).expect("rule saved");

        let updated = update_rule_from_draft(
            &repository,
            "builtin:domain:chatgpt.com",
            draft("openai.com", ProductivityCategory::Neutral),
        )
        .expect("rule updated");

        assert_eq!(updated.id, original.id);
        assert_eq!(updated.name, "openai.com");
        assert_eq!(updated.pattern, "openai.com");
        assert_eq!(updated.category, ProductivityCategory::Neutral);
        assert!(updated.is_builtin);
        assert_eq!(updated.priority, 0);
        assert!(updated.is_enabled);
    }

    #[test]
    fn rejects_uncategorized_rules() {
        let repository = Repository::in_memory_for_test().expect("repo");

        let error = create_rule_from_draft(
            &repository,
            draft("example.com", ProductivityCategory::Uncategorized),
        )
        .expect_err("uncategorized rule should be rejected");

        assert!(error.contains("Uncategorized"));
    }

    #[test]
    fn non_domain_patterns_with_different_text_do_not_collide() {
        let repository = Repository::in_memory_for_test().expect("repo");

        let spaced = create_rule_from_draft(
            &repository,
            typed_draft(
                RuleType::TitleKeyword,
                "deep work",
                ProductivityCategory::Productive,
            ),
        )
        .expect("created spaced rule");
        let hyphenated = create_rule_from_draft(
            &repository,
            typed_draft(
                RuleType::TitleKeyword,
                "deep-work",
                ProductivityCategory::Unproductive,
            ),
        )
        .expect("created hyphenated rule");

        assert_eq!(spaced.id, "user:titleKeyword:deep%20work");
        assert_eq!(hyphenated.id, "user:titleKeyword:deep-work");
        assert_ne!(spaced.id, hyphenated.id);

        let persisted = repository.list_rules().expect("rules");
        assert!(persisted.iter().any(|rule| rule.id == spaced.id));
        assert!(persisted.iter().any(|rule| rule.id == hyphenated.id));
    }

    #[test]
    fn classifies_persisted_today_sessions_and_derives_summary() {
        let repository = Repository::in_memory_for_test().expect("repo");
        let (start, _) = local_day_bounds_utc(Local::now().date_naive()).expect("bounds");
        let sessions = [
            activity_session(
                "productive",
                start + Duration::minutes(1),
                600,
                Some("chatgpt.com"),
                "Chrome",
                "chrome.exe",
                "ChatGPT",
                false,
            ),
            activity_session(
                "unknown",
                start + Duration::minutes(12),
                120,
                Some("unknown.example"),
                "Chrome",
                "chrome.exe",
                "Unknown",
                false,
            ),
            activity_session(
                "idle-youtube",
                start + Duration::minutes(20),
                60,
                Some("youtube.com"),
                "Chrome",
                "chrome.exe",
                "YouTube",
                true,
            ),
        ];
        for session in sessions {
            repository.save_session(&session).expect("session saved");
        }

        let classified = classified_sessions_for_local_today(&repository).expect("classified");
        let summary = summarize_sessions(&classified);
        let productive = classified
            .iter()
            .find(|session| session.id == "productive")
            .expect("productive session");
        let unknown = classified
            .iter()
            .find(|session| session.id == "unknown")
            .expect("unknown session");
        let idle = classified
            .iter()
            .find(|session| session.id == "idle-youtube")
            .expect("idle session");

        assert_eq!(productive.category, ProductivityCategory::Productive);
        assert_eq!(
            productive.matched_rule_id.as_deref(),
            Some("builtin:domain:chatgpt.com")
        );
        assert_eq!(unknown.category, ProductivityCategory::Uncategorized);
        assert_eq!(unknown.matched_rule_id, None);
        assert_eq!(idle.category, ProductivityCategory::Unproductive);
        assert!(idle.is_idle);
        assert_eq!(summary.tracked_seconds, 780);
        assert_eq!(summary.productive_seconds, 600);
        assert_eq!(summary.unproductive_seconds, 0);
        assert_eq!(summary.idle_seconds, 60);
        assert_eq!(summary.uncategorized_seconds, 120);
    }

    #[test]
    fn custom_rules_override_builtin_rules_in_command_sessions() {
        let repository = Repository::in_memory_for_test().expect("repo");
        let (start, _) = local_day_bounds_utc(Local::now().date_naive()).expect("bounds");
        let custom_rule = ClassificationRule {
            id: "user:domain:youtube.com".into(),
            name: "YouTube Learning".into(),
            rule_type: RuleType::Domain,
            pattern: "youtube.com".into(),
            category: ProductivityCategory::Productive,
            priority: 100,
            is_builtin: false,
            is_enabled: true,
        };
        repository.save_rule(&custom_rule).expect("rule saved");
        repository
            .save_session(&activity_session(
                "youtube",
                start + Duration::minutes(1),
                300,
                Some("youtube.com"),
                "Chrome",
                "chrome.exe",
                "YouTube",
                false,
            ))
            .expect("session saved");

        let classified = classified_sessions_for_local_today(&repository).expect("classified");
        let summary = summarize_sessions(&classified);

        assert_eq!(classified[0].category, ProductivityCategory::Productive);
        assert_eq!(
            classified[0].matched_rule_id.as_deref(),
            Some("user:domain:youtube.com")
        );
        assert_eq!(summary.productive_seconds, 300);
        assert_eq!(summary.unproductive_seconds, 0);
    }

    #[test]
    fn ignored_rules_remove_sessions_from_reports_until_reclassified() {
        let repository = Repository::in_memory_for_test().expect("repo");
        let (start, _) = local_day_bounds_utc(Local::now().date_naive()).expect("bounds");
        let ignored_rule = ClassificationRule {
            id: "user:domain:youtube.com".into(),
            name: "YouTube".into(),
            rule_type: RuleType::Domain,
            pattern: "youtube.com".into(),
            category: ProductivityCategory::Ignored,
            priority: 100,
            is_builtin: false,
            is_enabled: true,
        };
        repository
            .save_rule(&ignored_rule)
            .expect("ignored rule saved");
        repository
            .save_session(&activity_session(
                "youtube",
                start + Duration::minutes(1),
                300,
                Some("youtube.com"),
                "Chrome",
                "chrome.exe",
                "YouTube",
                false,
            ))
            .expect("session saved");

        let ignored = classified_sessions_for_local_today(&repository).expect("classified");
        let ignored_summary = summarize_sessions(&ignored);

        assert!(ignored.is_empty());
        assert_eq!(ignored_summary.tracked_seconds, 0);
        assert_eq!(ignored_summary.productive_seconds, 0);

        let restored_rule = ClassificationRule {
            category: ProductivityCategory::Productive,
            ..ignored_rule
        };
        repository
            .save_rule(&restored_rule)
            .expect("restored rule saved");

        let restored = classified_sessions_for_local_today(&repository).expect("classified");
        let restored_summary = summarize_sessions(&restored);

        assert_eq!(restored.len(), 1);
        assert_eq!(restored[0].category, ProductivityCategory::Productive);
        assert_eq!(
            restored[0].matched_rule_id.as_deref(),
            Some("user:domain:youtube.com")
        );
        assert_eq!(restored_summary.tracked_seconds, 300);
        assert_eq!(restored_summary.productive_seconds, 300);
    }

    #[test]
    fn local_today_sessions_use_local_day_boundaries() {
        let repository = Repository::in_memory_for_test().expect("repo");
        let (start, end) = local_day_bounds_utc(Local::now().date_naive()).expect("bounds");
        let sessions = [
            activity_session(
                "before",
                start - Duration::seconds(1),
                60,
                Some("chatgpt.com"),
                "Chrome",
                "chrome.exe",
                "Before",
                false,
            ),
            activity_session(
                "inside",
                start,
                60,
                Some("chatgpt.com"),
                "Chrome",
                "chrome.exe",
                "Inside",
                false,
            ),
            activity_session(
                "after",
                end,
                60,
                Some("chatgpt.com"),
                "Chrome",
                "chrome.exe",
                "After",
                false,
            ),
        ];
        for session in sessions {
            repository.save_session(&session).expect("session saved");
        }

        let classified = classified_sessions_for_local_today(&repository).expect("classified");

        assert_eq!(
            classified
                .iter()
                .map(|session| session.id.as_str())
                .collect::<Vec<_>>(),
            vec!["inside"]
        );
    }

    #[test]
    fn local_week_sessions_include_previous_six_local_days() {
        let repository = Repository::in_memory_for_test().expect("repo");
        let today = Local::now().date_naive();
        let (today_start, today_end) = local_day_bounds_utc(today).expect("today bounds");
        let week_start = local_day_bounds_utc(today - Duration::days(6))
            .expect("week start bounds")
            .0;
        let sessions = [
            activity_session(
                "before-week",
                week_start - Duration::seconds(1),
                60,
                Some("chatgpt.com"),
                "Chrome",
                "chrome.exe",
                "Before Week",
                false,
            ),
            activity_session(
                "week-start",
                week_start,
                60,
                Some("chatgpt.com"),
                "Chrome",
                "chrome.exe",
                "Week Start",
                false,
            ),
            activity_session(
                "yesterday",
                today_start - Duration::hours(2),
                60,
                Some("github.com"),
                "Chrome",
                "chrome.exe",
                "Yesterday",
                false,
            ),
            activity_session(
                "today",
                today_start,
                60,
                Some("chatgpt.com"),
                "Chrome",
                "chrome.exe",
                "Today",
                false,
            ),
            activity_session(
                "tomorrow",
                today_end,
                60,
                Some("chatgpt.com"),
                "Chrome",
                "chrome.exe",
                "Tomorrow",
                false,
            ),
        ];
        for session in sessions {
            repository.save_session(&session).expect("session saved");
        }

        let classified = classified_sessions_for_local_week(&repository).expect("classified");

        assert_eq!(
            classified
                .iter()
                .map(|session| session.id.as_str())
                .collect::<Vec<_>>(),
            vec!["week-start", "yesterday", "today"]
        );
    }
}
