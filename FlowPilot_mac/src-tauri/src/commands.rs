use chrono::{DateTime, Datelike, Local, NaiveDate, TimeZone, Timelike, Utc};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use tauri::State;
use uuid::Uuid;

use crate::app_state::AppState;
use crate::domain::activity::ActivitySession;
use crate::domain::classifier::classify;
use crate::domain::rules::{
    canonical_rule_pattern, ClassificationRule, ProductivityCategory, RuleType,
};
use crate::storage::repository::{
    ActivityGroup, ActivityGroupMatcher, DisplayNameOverride, Repository, SessionOverride,
};

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
    pub display_name: String,
    pub note: Option<String>,
    pub category_source: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HeatmapBucketDto {
    pub weekday: u32,
    pub hour: u32,
    pub seconds: i64,
    pub dominant_category: ProductivityCategory,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityGroupMatcherDto {
    pub id: String,
    pub rule_type: RuleType,
    pub pattern: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityGroupDto {
    pub id: String,
    pub name: String,
    pub color: String,
    pub matchers: Vec<ActivityGroupMatcherDto>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DisplayNameOverrideDto {
    pub id: String,
    pub rule_type: RuleType,
    pub pattern: String,
    pub display_name: String,
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
    let sessions = classified_sessions_for_local_today(&repository)?;

    Ok(summarize_sessions(&sessions))
}

#[tauri::command]
pub fn get_summary_for_range(
    state: State<AppState>,
    start: String,
    end: String,
) -> Result<TodaySummaryDto, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;
    let (start, end) = parse_report_range(&start, &end)?;
    let sessions = classified_sessions_for_range(&repository, start, end)?;

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
pub fn get_sessions_for_range(
    state: State<AppState>,
    start: String,
    end: String,
) -> Result<Vec<ActivitySessionDto>, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;
    let (start, end) = parse_report_range(&start, &end)?;

    classified_sessions_for_range(&repository, start, end)
}

#[tauri::command]
pub fn get_heatmap_for_range(
    state: State<AppState>,
    start: String,
    end: String,
) -> Result<Vec<HeatmapBucketDto>, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;
    let (start, end) = parse_report_range(&start, &end)?;
    let sessions = classified_sessions_for_range(&repository, start, end)?;

    Ok(build_heatmap(&sessions))
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

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityGroupMatcherDraftDto {
    pub rule_type: RuleType,
    pub pattern: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityGroupDraftDto {
    pub name: String,
    pub color: String,
    pub matchers: Vec<ActivityGroupMatcherDraftDto>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DisplayNameOverrideDraftDto {
    pub rule_type: RuleType,
    pub pattern: String,
    pub display_name: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionOverrideDraftDto {
    pub session_id: String,
    pub category_override: Option<ProductivityCategory>,
    pub display_name_override: Option<String>,
    pub note: Option<String>,
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

#[tauri::command]
pub fn list_activity_groups(state: State<AppState>) -> Result<Vec<ActivityGroupDto>, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;

    repository
        .list_groups()
        .map(|groups| groups.into_iter().map(ActivityGroupDto::from_group).collect())
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn create_activity_group(
    state: State<AppState>,
    draft: ActivityGroupDraftDto,
) -> Result<ActivityGroupDto, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;
    let group = group_from_draft(None, draft)?;

    repository
        .save_group(&group)
        .map_err(|error| error.to_string())?;

    Ok(ActivityGroupDto::from_group(group))
}

#[tauri::command]
pub fn update_activity_group(
    state: State<AppState>,
    group_id: String,
    draft: ActivityGroupDraftDto,
) -> Result<ActivityGroupDto, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;
    let group = group_from_draft(Some(group_id), draft)?;

    repository
        .save_group(&group)
        .map_err(|error| error.to_string())?;

    Ok(ActivityGroupDto::from_group(group))
}

#[tauri::command]
pub fn delete_activity_group(state: State<AppState>, group_id: String) -> Result<(), String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;

    repository
        .delete_group(&group_id)
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn list_display_name_overrides(
    state: State<AppState>,
) -> Result<Vec<DisplayNameOverrideDto>, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;

    repository
        .list_display_name_overrides()
        .map(|rows| {
            rows.into_iter()
                .map(DisplayNameOverrideDto::from_override)
                .collect()
        })
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn create_display_name_override(
    state: State<AppState>,
    draft: DisplayNameOverrideDraftDto,
) -> Result<DisplayNameOverrideDto, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;
    let override_row = display_name_override_from_draft(None, draft)?;

    repository
        .save_display_name_override(&override_row)
        .map_err(|error| error.to_string())?;

    Ok(DisplayNameOverrideDto::from_override(override_row))
}

#[tauri::command]
pub fn update_display_name_override(
    state: State<AppState>,
    override_id: String,
    draft: DisplayNameOverrideDraftDto,
) -> Result<DisplayNameOverrideDto, String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;
    let override_row = display_name_override_from_draft(Some(override_id), draft)?;

    repository
        .save_display_name_override(&override_row)
        .map_err(|error| error.to_string())?;

    Ok(DisplayNameOverrideDto::from_override(override_row))
}

#[tauri::command]
pub fn delete_display_name_override(
    state: State<AppState>,
    override_id: String,
) -> Result<(), String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;

    repository
        .delete_display_name_override(&override_id)
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn upsert_session_override(
    state: State<AppState>,
    draft: SessionOverrideDraftDto,
) -> Result<(), String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;
    let override_row = SessionOverride {
        session_id: draft.session_id,
        category_override: draft.category_override,
        display_name_override: trimmed_optional(draft.display_name_override),
        note: trimmed_optional(draft.note),
    };

    repository
        .upsert_session_override(&override_row)
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn delete_session_override(state: State<AppState>, session_id: String) -> Result<(), String> {
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;

    repository
        .delete_session_override(&session_id)
        .map_err(|error| error.to_string())
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
    let groups = repository
        .list_groups()
        .map_err(|error| error.to_string())?;
    let display_name_overrides = repository
        .list_display_name_overrides()
        .map_err(|error| error.to_string())?;

    let mut classified = Vec::with_capacity(sessions.len());

    for session in sessions {
        let override_row = repository
            .get_session_override(&session.id)
            .map_err(|error| error.to_string())?;
        let display_name = display_name_for_session(
            &session,
            &display_name_overrides,
            &groups,
            override_row.as_ref(),
        );
        let note = override_row.as_ref().and_then(|row| row.note.clone());
        let category_source = if override_row
            .as_ref()
            .and_then(|row| row.category_override)
            .is_some()
        {
            "override"
        } else {
            "automatic"
        }
        .to_string();
        let category = if let Some(category_override) =
            override_row.as_ref().and_then(|row| row.category_override)
        {
            category_override
        } else {
            let classification = classify(&session, &user_rules, &builtin_rules);
            let matched_rule_id = classification.matched_rule_id;
            let category = classification.category;
            if category == ProductivityCategory::Ignored {
                continue;
            }
            classified.push(ActivitySessionDto::from_session(
                session,
                category,
                matched_rule_id,
                display_name,
                note,
                category_source,
            ));
            continue;
        };

        if category == ProductivityCategory::Ignored {
            continue;
        }

        classified.push(ActivitySessionDto::from_session(
            session,
            category,
            None,
            display_name,
            note,
            category_source,
        ));
    }

    Ok(classified)
}

fn raw_sessions_for_local_today(repository: &Repository) -> Result<Vec<ActivitySession>, String> {
    let (start, end) = local_day_bounds_utc(Local::now().date_naive())?;
    repository
        .list_sessions_between(start, end)
        .map_err(|error| error.to_string())
}

fn parse_report_range(start: &str, end: &str) -> Result<(DateTime<Utc>, DateTime<Utc>), String> {
    let start = DateTime::parse_from_rfc3339(start)
        .map_err(|_| "리포트 시작 날짜를 해석할 수 없습니다.".to_string())?
        .with_timezone(&Utc);
    let end = DateTime::parse_from_rfc3339(end)
        .map_err(|_| "리포트 종료 날짜를 해석할 수 없습니다.".to_string())?
        .with_timezone(&Utc);

    if start >= end {
        return Err("리포트 종료 날짜는 시작 날짜보다 뒤여야 합니다.".into());
    }

    if end - start > chrono::Duration::days(180) {
        return Err("리포트 범위는 최대 180일까지 선택할 수 있습니다.".into());
    }

    Ok((start, end))
}

fn trimmed_optional(value: Option<String>) -> Option<String> {
    value.and_then(|raw| {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    })
}

fn group_from_draft(
    group_id: Option<String>,
    draft: ActivityGroupDraftDto,
) -> Result<ActivityGroup, String> {
    let name = draft.name.trim();
    if name.is_empty() {
        return Err("그룹 이름을 입력해야 합니다.".into());
    }

    if draft.matchers.is_empty() {
        return Err("그룹에는 최소 1개의 패턴이 필요합니다.".into());
    }

    let group_id = group_id.unwrap_or_else(|| format!("group:{}", Uuid::new_v4()));
    let mut matchers = Vec::with_capacity(draft.matchers.len());

    for (index, matcher) in draft.matchers.into_iter().enumerate() {
        let pattern = canonical_rule_pattern(matcher.rule_type, &matcher.pattern)
            .ok_or_else(|| "그룹 패턴을 입력해야 합니다.".to_string())?;
        matchers.push(ActivityGroupMatcher {
            id: format!("{group_id}:matcher:{index}"),
            group_id: group_id.clone(),
            rule_type: matcher.rule_type,
            pattern,
            priority: 100 - index as i64,
        });
    }

    Ok(ActivityGroup {
        id: group_id,
        name: name.to_string(),
        color: draft.color.trim().to_string(),
        matchers,
    })
}

fn display_name_override_from_draft(
    override_id: Option<String>,
    draft: DisplayNameOverrideDraftDto,
) -> Result<DisplayNameOverride, String> {
    let pattern = canonical_rule_pattern(draft.rule_type, &draft.pattern)
        .ok_or_else(|| "표시명을 적용할 식별값을 입력해야 합니다.".to_string())?;
    let display_name = draft.display_name.trim();
    if display_name.is_empty() {
        return Err("표시 이름을 입력해야 합니다.".into());
    }

    Ok(DisplayNameOverride {
        id: override_id.unwrap_or_else(|| {
            format!(
                "display-name:{}:{}",
                rule_type_id_segment(&draft.rule_type),
                pattern_id_segment(&pattern)
            )
        }),
        rule_type: draft.rule_type,
        pattern,
        display_name: display_name.to_string(),
        priority: 100,
    })
}

fn display_name_for_session(
    session: &ActivitySession,
    display_name_overrides: &[DisplayNameOverride],
    groups: &[ActivityGroup],
    override_row: Option<&SessionOverride>,
) -> String {
    if let Some(display_name_override) =
        override_row.and_then(|row| row.display_name_override.as_ref())
    {
        return display_name_override.clone();
    }

    if let Some(display_name_override) = best_display_name_override(session, display_name_overrides)
    {
        return display_name_override.display_name.clone();
    }

    groups
        .iter()
        .find(|group| {
            group
                .matchers
                .iter()
                .any(|matcher| group_matcher_matches_session(matcher, session))
        })
        .map(|group| group.name.clone())
        .unwrap_or_else(|| session.domain.clone().unwrap_or_else(|| session.app_name.clone()))
}

fn best_display_name_override<'a>(
    session: &ActivitySession,
    display_name_overrides: &'a [DisplayNameOverride],
) -> Option<&'a DisplayNameOverride> {
    display_name_overrides
        .iter()
        .filter(|override_row| {
            rule_type_pattern_matches_session(
                override_row.rule_type,
                &override_row.pattern,
                session,
            )
        })
        .max_by_key(|override_row| {
            (
                rule_type_specificity(override_row.rule_type),
                override_row.priority,
                override_row.pattern.len(),
            )
        })
}

fn group_matcher_matches_session(
    matcher: &ActivityGroupMatcher,
    session: &ActivitySession,
) -> bool {
    rule_type_pattern_matches_session(matcher.rule_type, &matcher.pattern, session)
}

fn rule_type_pattern_matches_session(
    rule_type: RuleType,
    pattern: &str,
    session: &ActivitySession,
) -> bool {
    match rule_type {
        RuleType::Domain => {
            let Some(domain) = session
                .domain
                .as_ref()
                .and_then(|value| canonical_rule_pattern(RuleType::Domain, value))
            else {
                return false;
            };
            let Some(pattern) = canonical_rule_pattern(RuleType::Domain, pattern) else {
                return false;
            };

            domain == pattern || domain.ends_with(&format!(".{pattern}"))
        }
        RuleType::App => {
            session.process_name.eq_ignore_ascii_case(pattern)
                || session.app_name.eq_ignore_ascii_case(pattern)
        }
        RuleType::TitleKeyword => session
            .window_title
            .to_lowercase()
            .contains(&pattern.to_lowercase()),
        RuleType::UrlPattern => session
            .url
            .as_ref()
            .map(|url| url.to_lowercase().contains(&pattern.to_lowercase()))
            .unwrap_or(false),
    }
}

fn rule_type_specificity(rule_type: RuleType) -> i32 {
    match rule_type {
        RuleType::UrlPattern => 40,
        RuleType::Domain => 30,
        RuleType::App => 20,
        RuleType::TitleKeyword => 10,
    }
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

fn build_heatmap(sessions: &[ActivitySessionDto]) -> Vec<HeatmapBucketDto> {
    let mut buckets: BTreeMap<(u32, u32), [i64; 5]> = BTreeMap::new();

    for session in sessions {
        let local_start = session.started_at.with_timezone(&Local);
        let key = (
            local_start.weekday().num_days_from_monday(),
            local_start.hour(),
        );
        let totals = buckets.entry(key).or_insert([0; 5]);
        totals[category_index(session.category)] += session.duration_seconds;
    }

    buckets
        .into_iter()
        .map(|((weekday, hour), totals)| {
            let (dominant_index, _dominant_seconds) = totals
                .iter()
                .enumerate()
                .max_by_key(|(_, seconds)| **seconds)
                .map(|(index, seconds)| (index, *seconds))
                .unwrap_or((4, 0));

            HeatmapBucketDto {
                weekday,
                hour,
                seconds: totals.iter().sum(),
                dominant_category: category_from_index(dominant_index),
            }
        })
        .filter(|bucket| bucket.seconds > 0)
        .collect()
}

fn category_index(category: ProductivityCategory) -> usize {
    match category {
        ProductivityCategory::Productive => 0,
        ProductivityCategory::Unproductive => 1,
        ProductivityCategory::Neutral => 2,
        ProductivityCategory::Ignored => 3,
        ProductivityCategory::Uncategorized => 4,
    }
}

fn category_from_index(index: usize) -> ProductivityCategory {
    match index {
        0 => ProductivityCategory::Productive,
        1 => ProductivityCategory::Unproductive,
        2 => ProductivityCategory::Neutral,
        3 => ProductivityCategory::Ignored,
        _ => ProductivityCategory::Uncategorized,
    }
}

impl ActivitySessionDto {
    fn from_session(
        session: ActivitySession,
        category: ProductivityCategory,
        matched_rule_id: Option<String>,
        display_name: String,
        note: Option<String>,
        category_source: String,
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
            display_name,
            note,
            category_source,
        }
    }
}

impl ActivityGroupDto {
    fn from_group(group: ActivityGroup) -> Self {
        Self {
            id: group.id,
            name: group.name,
            color: group.color,
            matchers: group
                .matchers
                .into_iter()
                .map(|matcher| ActivityGroupMatcherDto {
                    id: matcher.id,
                    rule_type: matcher.rule_type,
                    pattern: matcher.pattern,
                })
                .collect(),
        }
    }
}

impl DisplayNameOverrideDto {
    fn from_override(override_row: DisplayNameOverride) -> Self {
        Self {
            id: override_row.id,
            rule_type: override_row.rule_type,
            pattern: override_row.pattern,
            display_name: override_row.display_name,
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
    use crate::storage::repository::{DisplayNameOverride, Repository};
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
        repository
            .save_rule(&ClassificationRule {
                id: "user:domain:ignored.example".into(),
                name: "Ignored Example".into(),
                rule_type: RuleType::Domain,
                pattern: "ignored.example".into(),
                category: ProductivityCategory::Ignored,
                priority: 100,
                is_builtin: false,
                is_enabled: true,
            })
            .expect("ignored rule saved");
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
            activity_session(
                "ignored",
                start + Duration::minutes(30),
                300,
                Some("ignored.example"),
                "Chrome",
                "chrome.exe",
                "Ignored",
                false,
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

        assert!(
            classified.iter().all(|session| session.id != "ignored"),
            "ignored sessions should not be returned to reports"
        );
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
    fn global_display_name_overrides_apply_to_matching_sessions_until_removed() {
        let repository = Repository::in_memory_for_test().expect("repo");
        let (start, _) = local_day_bounds_utc(Local::now().date_naive()).expect("bounds");
        repository
            .save_session(&activity_session(
                "explorer",
                start + Duration::minutes(1),
                300,
                None,
                "explorer.exe",
                "explorer.exe",
                "Downloads",
                false,
            ))
            .expect("session saved");
        repository
            .save_display_name_override(&DisplayNameOverride {
                id: "display-name:app:explorer.exe".into(),
                rule_type: RuleType::App,
                pattern: "explorer.exe".into(),
                display_name: "파일 탐색기".into(),
                priority: 100,
            })
            .expect("display name override saved");

        let renamed = classified_sessions_for_local_today(&repository).expect("classified");
        assert_eq!(renamed[0].display_name, "파일 탐색기");

        repository
            .delete_display_name_override("display-name:app:explorer.exe")
            .expect("display name override deleted");
        let restored = classified_sessions_for_local_today(&repository).expect("classified");
        assert_eq!(restored[0].display_name, "explorer.exe");
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
}
