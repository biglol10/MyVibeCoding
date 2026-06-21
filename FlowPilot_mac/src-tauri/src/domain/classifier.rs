use super::activity::ActivitySession;
use super::rules::{canonical_rule_pattern, ClassificationRule, ProductivityCategory, RuleType};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClassificationResult {
    pub category: ProductivityCategory,
    pub matched_rule_id: Option<String>,
}

pub fn classify(
    session: &ActivitySession,
    user_rules: &[ClassificationRule],
    builtin_rules: &[ClassificationRule],
) -> ClassificationResult {
    user_rules
        .iter()
        .filter(|rule| rule.is_enabled)
        .filter(|rule| matches_rule(rule, session))
        .max_by_key(|rule| rule.classification_order_key())
        .or_else(|| {
            builtin_rules
                .iter()
                .filter(|rule| rule.is_enabled)
                .filter(|rule| matches_rule(rule, session))
                .max_by_key(|rule| rule.classification_order_key())
        })
        .map(|rule| ClassificationResult {
            category: rule.category,
            matched_rule_id: Some(rule.id.clone()),
        })
        .unwrap_or(ClassificationResult {
            category: ProductivityCategory::Uncategorized,
            matched_rule_id: None,
        })
}

fn matches_rule(rule: &ClassificationRule, session: &ActivitySession) -> bool {
    match rule.rule_type {
        RuleType::Domain => {
            let Some(domain) = session
                .domain
                .as_deref()
                .and_then(|domain| canonical_rule_pattern(RuleType::Domain, domain))
            else {
                return false;
            };
            let Some(pattern) = canonical_rule_pattern(RuleType::Domain, &rule.pattern) else {
                return false;
            };

            domain == pattern
                || domain.ends_with(&format!(".{pattern}"))
                || domain
                    .strip_prefix("www.")
                    .map(|without_www| without_www == pattern)
                    .unwrap_or(false)
        }
        RuleType::App => {
            session.process_name.eq_ignore_ascii_case(&rule.pattern)
                || session.app_name.eq_ignore_ascii_case(&rule.pattern)
        }
        RuleType::TitleKeyword => non_empty_pattern(&rule.pattern)
            .map(|pattern| session.window_title.to_lowercase().contains(&pattern))
            .unwrap_or(false),
        RuleType::UrlPattern => {
            let Some(pattern) = non_empty_pattern(&rule.pattern) else {
                return false;
            };

            session
                .url
                .as_deref()
                .map(|url| url.to_lowercase().contains(&pattern))
                .unwrap_or(false)
        }
    }
}

fn non_empty_pattern(value: &str) -> Option<String> {
    let pattern = value.trim().to_lowercase();

    if pattern.is_empty() {
        None
    } else {
        Some(pattern)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::activity::ActivitySource;
    use chrono::Utc;

    fn session(domain: Option<&str>, app: &str, title: &str) -> ActivitySession {
        ActivitySession {
            id: "s1".into(),
            started_at: Utc::now(),
            ended_at: Utc::now(),
            duration_seconds: 60,
            source: ActivitySource::ActiveWindow,
            app_name: app.into(),
            process_name: app.into(),
            window_title: title.into(),
            domain: domain.map(str::to_string),
            url: None,
            is_idle: false,
        }
    }

    fn rule(
        id: &str,
        rule_type: RuleType,
        pattern: &str,
        category: ProductivityCategory,
        is_builtin: bool,
    ) -> ClassificationRule {
        ClassificationRule {
            id: id.into(),
            name: id.into(),
            rule_type,
            pattern: pattern.into(),
            category,
            priority: 0,
            is_builtin,
            is_enabled: true,
        }
    }

    #[test]
    fn user_rules_override_builtin_rules() {
        let user_rule = rule(
            "user:youtube",
            RuleType::Domain,
            "youtube.com",
            ProductivityCategory::Productive,
            false,
        );
        let builtin_rule = rule(
            "builtin:youtube",
            RuleType::Domain,
            "youtube.com",
            ProductivityCategory::Unproductive,
            true,
        );

        let result = classify(
            &session(Some("youtube.com"), "chrome.exe", "Lecture - YouTube"),
            &[user_rule],
            &[builtin_rule],
        );

        assert_eq!(result.category, ProductivityCategory::Productive);
        assert_eq!(result.matched_rule_id.as_deref(), Some("user:youtube"));
    }

    #[test]
    fn subdomains_beat_parent_domains() {
        let parent = rule(
            "builtin:naver",
            RuleType::Domain,
            "naver.com",
            ProductivityCategory::Neutral,
            true,
        );
        let child = rule(
            "builtin:chzzk",
            RuleType::Domain,
            "chzzk.naver.com",
            ProductivityCategory::Unproductive,
            true,
        );

        let result = classify(
            &session(Some("chzzk.naver.com"), "chrome.exe", "Chzzk"),
            &[],
            &[parent, child],
        );

        assert_eq!(result.category, ProductivityCategory::Unproductive);
        assert_eq!(result.matched_rule_id.as_deref(), Some("builtin:chzzk"));
    }

    #[test]
    fn title_keyword_matches_when_domain_is_missing() {
        let keyword = rule(
            "builtin:title:chatgpt",
            RuleType::TitleKeyword,
            "ChatGPT",
            ProductivityCategory::Productive,
            true,
        );

        let result = classify(
            &session(None, "chrome.exe", "ChatGPT - Google Chrome"),
            &[],
            &[keyword],
        );

        assert_eq!(result.category, ProductivityCategory::Productive);
    }

    #[test]
    fn domain_match_normalizes_case_whitespace_trailing_dot_and_www_prefix() {
        let youtube = rule(
            "builtin:youtube",
            RuleType::Domain,
            "youtube.com",
            ProductivityCategory::Unproductive,
            true,
        );

        let result = classify(
            &session(
                Some("  WWW.YouTube.COM. "),
                "chrome.exe",
                "Lecture - YouTube",
            ),
            &[],
            &[youtube],
        );

        assert_eq!(result.category, ProductivityCategory::Unproductive);
        assert_eq!(result.matched_rule_id.as_deref(), Some("builtin:youtube"));
    }

    #[test]
    fn domain_match_normalizes_www_prefix_on_rule_pattern() {
        let youtube = rule(
            "user:youtube",
            RuleType::Domain,
            "www.youtube.com",
            ProductivityCategory::Productive,
            false,
        );

        let result = classify(
            &session(Some("youtube.com"), "chrome.exe", "Lecture - YouTube"),
            &[youtube],
            &[],
        );

        assert_eq!(result.category, ProductivityCategory::Productive);
        assert_eq!(result.matched_rule_id.as_deref(), Some("user:youtube"));
    }

    #[test]
    fn empty_title_keyword_pattern_does_not_match() {
        let keyword = rule(
            "builtin:title:empty",
            RuleType::TitleKeyword,
            "",
            ProductivityCategory::Productive,
            true,
        );

        let result = classify(
            &session(None, "chrome.exe", "ChatGPT - Google Chrome"),
            &[],
            &[keyword],
        );

        assert_eq!(result.category, ProductivityCategory::Uncategorized);
        assert_eq!(result.matched_rule_id, None);
    }

    #[test]
    fn whitespace_only_url_pattern_does_not_match() {
        let url_rule = rule(
            "builtin:url:blank",
            RuleType::UrlPattern,
            "   ",
            ProductivityCategory::Unproductive,
            true,
        );
        let mut active = session(Some("example.com"), "chrome.exe", "Example");
        active.url = Some("https://example.com/   /docs".into());

        let result = classify(&active, &[], &[url_rule]);

        assert_eq!(result.category, ProductivityCategory::Uncategorized);
        assert_eq!(result.matched_rule_id, None);
    }

    #[test]
    fn url_pattern_matching_is_case_insensitive() {
        let url_rule = rule(
            "builtin:url:docs",
            RuleType::UrlPattern,
            "/DOCS",
            ProductivityCategory::Productive,
            true,
        );
        let mut active = session(Some("example.com"), "chrome.exe", "Example");
        active.url = Some("https://example.com/docs/getting-started".into());

        let result = classify(&active, &[], &[url_rule]);

        assert_eq!(result.category, ProductivityCategory::Productive);
        assert_eq!(result.matched_rule_id.as_deref(), Some("builtin:url:docs"));
    }
}
