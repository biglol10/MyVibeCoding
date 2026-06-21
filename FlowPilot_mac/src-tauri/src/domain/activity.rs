use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use super::rules::ProductivityCategory;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ActivitySource {
    ActiveWindow,
    BrowserExtension,
    Idle,
    Manual,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivitySession {
    pub id: String,
    pub started_at: DateTime<Utc>,
    pub ended_at: DateTime<Utc>,
    pub duration_seconds: i64,
    pub source: ActivitySource,
    pub app_name: String,
    pub process_name: String,
    pub window_title: String,
    pub domain: Option<String>,
    pub url: Option<String>,
    pub is_idle: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClassifiedSession {
    pub session: ActivitySession,
    pub category: ProductivityCategory,
    pub matched_rule_id: Option<String>,
}
