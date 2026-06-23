use chrono::{DateTime, Utc};

use crate::collector::session_merger::ActivitySample;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WindowObservation {
    pub observed_at: DateTime<Utc>,
    pub app_name: String,
    pub process_name: String,
    pub pid: Option<u32>,
    pub bundle_identifier: Option<String>,
    pub window_title: Option<String>,
    pub is_visible: bool,
    pub is_frontmost: bool,
    pub is_primary: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActivitySnapshot {
    pub primary: ActivitySample,
    pub visible_windows: Vec<WindowObservation>,
}

pub trait ActivitySnapshotReader: Send + Sync {
    fn read_snapshot(&self) -> anyhow::Result<ActivitySnapshot>;
}

impl ActivitySnapshot {
    pub fn from_primary(primary: ActivitySample) -> Self {
        let visible_windows = vec![WindowObservation {
            observed_at: primary.observed_at,
            app_name: primary.app_name.clone(),
            process_name: primary.process_name.clone(),
            pid: None,
            bundle_identifier: None,
            window_title: Some(primary.window_title.clone()),
            is_visible: true,
            is_frontmost: true,
            is_primary: true,
        }];

        Self {
            primary,
            visible_windows,
        }
    }
}

pub fn choose_primary_observation<'a>(
    observations: &'a [WindowObservation],
    own_bundle_identifier: Option<&str>,
) -> Option<&'a WindowObservation> {
    observations
        .iter()
        .find(|observation| {
            observation.is_frontmost && !is_own_app(observation, own_bundle_identifier)
        })
        .or_else(|| {
            observations.iter().find(|observation| {
                observation.is_visible && !is_own_app(observation, own_bundle_identifier)
            })
        })
        .or_else(|| {
            observations
                .iter()
                .find(|observation| observation.is_frontmost)
        })
        .or_else(|| {
            observations
                .iter()
                .find(|observation| observation.is_visible)
        })
}

fn is_own_app(observation: &WindowObservation, own_bundle_identifier: Option<&str>) -> bool {
    own_bundle_identifier
        .and_then(|own| {
            observation
                .bundle_identifier
                .as_deref()
                .map(|bundle| bundle == own)
        })
        .unwrap_or(false)
        || observation.app_name.eq_ignore_ascii_case("FlowPilot")
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn observed_at() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 6, 19, 9, 0, 0).unwrap()
    }

    fn observation(app_name: &str, is_frontmost: bool, is_primary: bool) -> WindowObservation {
        WindowObservation {
            observed_at: observed_at(),
            app_name: app_name.into(),
            process_name: format!("{app_name}.app"),
            pid: Some(42),
            bundle_identifier: Some(format!("com.example.{app_name}")),
            window_title: Some(format!("{app_name} title")),
            is_visible: true,
            is_frontmost,
            is_primary,
        }
    }

    #[test]
    fn snapshot_from_primary_marks_one_visible_observation_as_primary() {
        let sample = ActivitySample {
            observed_at: observed_at(),
            app_name: "Safari".into(),
            process_name: "Safari".into(),
            window_title: "Apple Developer".into(),
            domain: None,
            is_idle: false,
        };

        let snapshot = ActivitySnapshot::from_primary(sample.clone());

        assert_eq!(snapshot.primary, sample);
        assert_eq!(snapshot.visible_windows.len(), 1);
        assert!(snapshot.visible_windows[0].is_primary);
        assert!(snapshot.visible_windows[0].is_frontmost);
        assert_eq!(
            snapshot.visible_windows[0].window_title.as_deref(),
            Some("Apple Developer")
        );
    }

    #[test]
    fn chooses_frontmost_non_flowpilot_window_as_primary() {
        let flowpilot = observation("FlowPilot", true, false);
        let code = observation("Code", true, false);
        let finder = observation("Finder", false, false);

        let observations = [flowpilot, finder, code];
        let selected = choose_primary_observation(&observations, Some("com.example.FlowPilot"))
            .expect("primary observation");

        assert_eq!(selected.app_name, "Code");
    }

    #[test]
    fn falls_back_to_first_visible_non_flowpilot_window() {
        let flowpilot = observation("FlowPilot", false, false);
        let notes = observation("Notes", false, false);

        let observations = [flowpilot, notes];
        let selected = choose_primary_observation(&observations, Some("com.example.FlowPilot"))
            .expect("fallback observation");

        assert_eq!(selected.app_name, "Notes");
    }
}
