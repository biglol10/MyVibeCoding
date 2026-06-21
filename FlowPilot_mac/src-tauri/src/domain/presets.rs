use super::rules::{ClassificationRule, ProductivityCategory, RuleType};

fn rule(
    id: &str,
    name: &str,
    rule_type: RuleType,
    pattern: &str,
    category: ProductivityCategory,
    priority: i32,
) -> ClassificationRule {
    ClassificationRule {
        id: id.to_string(),
        name: name.to_string(),
        rule_type,
        pattern: pattern.to_string(),
        category,
        priority,
        is_builtin: true,
        is_enabled: true,
    }
}

pub fn default_rules() -> Vec<ClassificationRule> {
    let productive_domains = [
        ("chatgpt.com", "ChatGPT"),
        ("chat.openai.com", "ChatGPT Legacy"),
        ("openai.com", "OpenAI"),
        ("platform.openai.com", "OpenAI Platform"),
        ("claude.ai", "Claude"),
        ("github.com", "GitHub"),
        ("gitlab.com", "GitLab"),
        ("stackoverflow.com", "Stack Overflow"),
        ("developer.mozilla.org", "MDN"),
        ("learn.microsoft.com", "Microsoft Learn"),
        ("docs.google.com", "Google Docs"),
        ("notion.so", "Notion"),
        ("figma.com", "Figma"),
        ("linear.app", "Linear"),
        ("atlassian.net", "Atlassian"),
    ];

    let unproductive_domains = [
        ("youtube.com", "YouTube"),
        ("instagram.com", "Instagram"),
        ("tiktok.com", "TikTok"),
        ("x.com", "X"),
        ("twitter.com", "Twitter"),
        ("facebook.com", "Facebook"),
        ("netflix.com", "Netflix"),
        ("disneyplus.com", "Disney+"),
        ("twitch.tv", "Twitch"),
        ("chzzk.naver.com", "Chzzk"),
        ("sooplive.co.kr", "SOOP"),
        ("webtoon.naver.com", "Naver Webtoon"),
        ("comic.naver.com", "Naver Comic"),
    ];

    let neutral_domains = [
        ("google.com", "Google"),
        ("naver.com", "Naver"),
        ("bing.com", "Bing"),
        ("gmail.com", "Gmail"),
        ("mail.google.com", "Google Mail"),
        ("drive.google.com", "Google Drive"),
        ("reddit.com", "Reddit"),
        ("discord.com", "Discord"),
        ("slack.com", "Slack"),
        ("teams.microsoft.com", "Microsoft Teams"),
        ("calendar.google.com", "Google Calendar"),
        ("shopping.naver.com", "Naver Shopping"),
        ("coupang.com", "Coupang"),
    ];

    productive_domains
        .into_iter()
        .map(|(pattern, name)| {
            rule(
                &format!("builtin:domain:{pattern}"),
                name,
                RuleType::Domain,
                pattern,
                ProductivityCategory::Productive,
                0,
            )
        })
        .chain(unproductive_domains.into_iter().map(|(pattern, name)| {
            rule(
                &format!("builtin:domain:{pattern}"),
                name,
                RuleType::Domain,
                pattern,
                ProductivityCategory::Unproductive,
                0,
            )
        }))
        .chain(neutral_domains.into_iter().map(|(pattern, name)| {
            rule(
                &format!("builtin:domain:{pattern}"),
                name,
                RuleType::Domain,
                pattern,
                ProductivityCategory::Neutral,
                0,
            )
        }))
        .collect()
}
