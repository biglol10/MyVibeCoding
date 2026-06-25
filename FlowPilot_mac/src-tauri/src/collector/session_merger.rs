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
    if current.app_name != next.app_name
        || current.process_name != next.process_name
        || current.domain != next.domain
        || current.is_idle != next.is_idle
    {
        return false;
    }

    normalized_title(&current.window_title) == normalized_title(&next.window_title)
        || is_generic_fallback_title(current, &current.window_title)
        || is_generic_fallback_title(next, &next.window_title)
}

pub fn merged_sample(current: &ActivitySample, next: &ActivitySample) -> ActivitySample {
    ActivitySample {
        observed_at: next.observed_at,
        app_name: next.app_name.clone(),
        process_name: next.process_name.clone(),
        window_title: preferred_title(current, next),
        domain: next.domain.clone().or_else(|| current.domain.clone()),
        is_idle: next.is_idle,
    }
}

fn preferred_title(current: &ActivitySample, next: &ActivitySample) -> String {
    let current_generic = is_generic_fallback_title(current, &current.window_title);
    let next_generic = is_generic_fallback_title(next, &next.window_title);

    if current_generic && !next_generic {
        return next.window_title.clone();
    }

    if !current_generic && next_generic {
        return current.window_title.clone();
    }

    next.window_title.clone()
}

fn is_generic_fallback_title(sample: &ActivitySample, title: &str) -> bool {
    let normalized = normalized_title(title);
    normalized == normalized_title(&sample.app_name)
        || normalized == normalized_title(&sample.process_name)
}

fn normalized_title(value: &str) -> String {
    value
        .trim()
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
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

    fn app_sample(app_name: &str, title: &str) -> ActivitySample {
        ActivitySample {
            observed_at: Utc::now(),
            app_name: app_name.into(),
            process_name: app_name.into(),
            window_title: title.into(),
            domain: None,
            is_idle: false,
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

    #[test]
    fn merges_generic_fallback_titles_for_the_same_app() {
        assert!(should_merge(
            &app_sample("Calendar", "Calendar"),
            &app_sample("Calendar", "Holidays")
        ));
        assert!(should_merge(
            &app_sample("Calendar", "Holidays"),
            &app_sample("Calendar", "Calendar")
        ));
    }
}
