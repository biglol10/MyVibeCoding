use chrono::{DateTime, Utc};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActivitySample {
    pub observed_at: DateTime<Utc>,
    pub app_name: String,
    pub process_name: String,
    pub window_title: String,
    pub domain: Option<String>,
    pub is_idle: bool,
}

pub fn should_merge(current: &ActivitySample, next: &ActivitySample) -> bool {
    current.app_name == next.app_name
        && current.process_name == next.process_name
        && current.window_title == next.window_title
        && current.domain == next.domain
        && current.is_idle == next.is_idle
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    fn sample(title: &str, domain: Option<&str>, is_idle: bool) -> ActivitySample {
        ActivitySample {
            observed_at: Utc::now(),
            app_name: "Chrome".into(),
            process_name: "chrome.exe".into(),
            window_title: title.into(),
            domain: domain.map(str::to_string),
            is_idle,
        }
    }

    #[test]
    fn merges_same_domain_title_and_idle_state() {
        assert!(should_merge(
            &sample("ChatGPT", Some("chatgpt.com"), false),
            &sample("ChatGPT", Some("chatgpt.com"), false)
        ));
    }

    #[test]
    fn splits_when_idle_state_changes() {
        assert!(!should_merge(
            &sample("ChatGPT", Some("chatgpt.com"), false),
            &sample("ChatGPT", Some("chatgpt.com"), true)
        ));
    }
}
