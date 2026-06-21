use crate::domain::activity::ActivitySession;

pub fn sessions_to_csv(sessions: &[ActivitySession]) -> String {
    let mut csv =
        String::from("started_at,ended_at,duration_seconds,app_name,domain,window_title\n");
    for session in sessions {
        csv.push_str(&format!(
            "{},{},{},{},{},{}\n",
            session.started_at.to_rfc3339(),
            session.ended_at.to_rfc3339(),
            session.duration_seconds,
            sanitize_csv_cell(&session.app_name),
            sanitize_csv_cell(session.domain.as_deref().unwrap_or_default()),
            sanitize_csv_cell(&session.window_title)
        ));
    }
    csv
}

fn sanitize_csv_cell(value: &str) -> String {
    let mut safe_value = if starts_with_formula_prefix(value) {
        format!("'{value}")
    } else {
        value.to_string()
    };

    if safe_value.contains([',', '"', '\n', '\r']) {
        safe_value = safe_value.replace('"', "\"\"");
        format!("\"{safe_value}\"")
    } else {
        safe_value
    }
}

fn starts_with_formula_prefix(value: &str) -> bool {
    matches!(value.chars().next(), Some('=' | '+' | '-' | '@'))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::activity::{ActivitySession, ActivitySource};
    use chrono::Utc;

    #[test]
    fn exports_session_headers_and_rows() {
        let now = Utc::now();
        let csv = sessions_to_csv(&[ActivitySession {
            id: "s1".into(),
            started_at: now,
            ended_at: now,
            duration_seconds: 60,
            source: ActivitySource::ActiveWindow,
            app_name: "Chrome".into(),
            process_name: "chrome.exe".into(),
            window_title: "ChatGPT".into(),
            domain: Some("chatgpt.com".into()),
            url: None,
            is_idle: false,
        }]);

        assert!(csv.contains("started_at,ended_at,duration_seconds,app_name,domain,window_title"));
        assert!(csv.contains("chatgpt.com"));
    }

    #[test]
    fn escapes_csv_cells_and_prefixes_formula_like_text() {
        let now = Utc::now();
        let csv = sessions_to_csv(&[ActivitySession {
            id: "s1".into(),
            started_at: now,
            ended_at: now,
            duration_seconds: 60,
            source: ActivitySource::ActiveWindow,
            app_name: "Chrome, Beta".into(),
            process_name: "chrome.exe".into(),
            window_title: "=SUM(1,1)\nNext".into(),
            domain: Some("docs\"google.com".into()),
            url: None,
            is_idle: false,
        }]);

        assert!(csv.contains("\"Chrome, Beta\""));
        assert!(csv.contains("\"docs\"\"google.com\""));
        assert!(csv.contains("\"'=SUM(1,1)\nNext\""));
    }
}
