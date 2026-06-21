use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ProductivityCategory {
    Productive,
    Unproductive,
    Neutral,
    Ignored,
    Uncategorized,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RuleType {
    Domain,
    App,
    TitleKeyword,
    UrlPattern,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClassificationRule {
    pub id: String,
    pub name: String,
    pub rule_type: RuleType,
    pub pattern: String,
    pub category: ProductivityCategory,
    pub priority: i32,
    pub is_builtin: bool,
    pub is_enabled: bool,
}

impl ClassificationRule {
    pub fn rule_type_specificity(&self) -> i32 {
        match self.rule_type {
            RuleType::UrlPattern => 40,
            RuleType::Domain => 30,
            RuleType::App => 20,
            RuleType::TitleKeyword => 10,
        }
    }

    pub fn classification_order_key(&self) -> (i32, i32, i32) {
        (
            self.rule_type_specificity(),
            self.priority,
            self.pattern.len() as i32,
        )
    }

    /// Type-only specificity score. Prefer `classification_order_key` when ordering rules.
    pub fn specificity(&self) -> i32 {
        self.rule_type_specificity()
    }
}

pub fn canonical_rule_pattern(rule_type: RuleType, pattern: &str) -> Option<String> {
    match rule_type {
        RuleType::Domain => {
            let normalized = pattern.trim().to_lowercase();
            let normalized = normalized.strip_prefix("www.").unwrap_or(&normalized);
            let normalized = normalized.trim_end_matches('.');

            if normalized.is_empty() {
                None
            } else {
                Some(normalized.to_string())
            }
        }
        RuleType::App | RuleType::TitleKeyword | RuleType::UrlPattern => {
            let trimmed = pattern.trim();

            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_rule(rule_type: RuleType, pattern: &str, priority: i32) -> ClassificationRule {
        ClassificationRule {
            id: format!("test:{pattern}"),
            name: pattern.into(),
            rule_type,
            pattern: pattern.into(),
            category: ProductivityCategory::Neutral,
            priority,
            is_builtin: true,
            is_enabled: true,
        }
    }

    #[test]
    fn domain_rules_are_more_specific_than_app_rules() {
        let domain = test_rule(RuleType::Domain, "docs.google.com", 0);
        let app = test_rule(RuleType::App, "chrome.exe", 0);

        assert!(domain.rule_type_specificity() > app.rule_type_specificity());
        assert!(domain.specificity() > app.specificity());
    }

    #[test]
    fn higher_priority_rules_sort_after_lower_priority_rules() {
        let lower_priority = test_rule(RuleType::Domain, "example.com", 0);
        let higher_priority = test_rule(RuleType::Domain, "example.com", 10);

        assert!(
            higher_priority.classification_order_key() > lower_priority.classification_order_key()
        );
    }

    #[test]
    fn longer_domain_pattern_sorts_after_parent_domain_when_priority_matches() {
        let parent_domain = test_rule(RuleType::Domain, "naver.com", 0);
        let subdomain = test_rule(RuleType::Domain, "chzzk.naver.com", 0);

        assert!(subdomain.classification_order_key() > parent_domain.classification_order_key());
    }

    #[test]
    fn canonical_rule_pattern_normalizes_domain_variants() {
        assert_eq!(
            canonical_rule_pattern(RuleType::Domain, " WWW.YouTube.COM. "),
            Some("youtube.com".into())
        );
        assert_eq!(
            canonical_rule_pattern(RuleType::Domain, "youtube.com."),
            Some("youtube.com".into())
        );
    }

    #[test]
    fn canonical_rule_pattern_rejects_empty_domains_after_www_is_removed() {
        assert_eq!(canonical_rule_pattern(RuleType::Domain, " www. "), None);
    }

    #[test]
    fn canonical_rule_pattern_trims_non_domain_patterns_without_lowercasing() {
        assert_eq!(
            canonical_rule_pattern(RuleType::App, " Code.exe "),
            Some("Code.exe".into())
        );
        assert_eq!(
            canonical_rule_pattern(RuleType::TitleKeyword, "  Deep Work  "),
            Some("Deep Work".into())
        );
        assert_eq!(
            canonical_rule_pattern(RuleType::UrlPattern, "  /Watch  "),
            Some("/Watch".into())
        );
    }
}
