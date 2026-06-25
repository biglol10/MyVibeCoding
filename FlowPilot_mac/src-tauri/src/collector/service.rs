use std::sync::{Arc, Mutex};
use std::time::Duration;

use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::app_state::TrackingStatus;
#[cfg(target_os = "windows")]
use crate::collector::active_window::WindowsActiveWindowReader;
use crate::collector::session_merger::{merged_sample, should_merge, ActivitySample};
use crate::collector::snapshot::{ActivitySnapshot, ActivitySnapshotReader, WindowObservation};
use crate::domain::activity::{ActivitySession, ActivitySource};
use crate::storage::repository::{BrowserEvent, Repository};

const BROWSER_EVENT_MATCHED_TITLE_MAX_AGE_SECONDS: i64 = 12 * 60 * 60;
const BROWSER_EVENT_RECENT_FALLBACK_MAX_AGE_SECONDS: i64 = 30;

pub struct CollectorService<R> {
    reader: R,
    repository: Arc<Mutex<Repository>>,
    pub sample_interval: Duration,
    tracking_status: Arc<Mutex<TrackingStatus>>,
}

impl<R> CollectorService<R>
where
    R: ActivitySnapshotReader + 'static,
{
    pub fn new(
        sample_interval: Duration,
        reader: R,
        repository: Arc<Mutex<Repository>>,
        tracking_status: Arc<Mutex<TrackingStatus>>,
    ) -> Self {
        Self {
            reader,
            repository,
            sample_interval,
            tracking_status,
        }
    }

    pub fn start(self) {
        let mut accumulator = ActivitySessionAccumulator::new();

        std::thread::spawn(move || loop {
            std::thread::sleep(self.sample_interval);

            if tracking_is_paused(&self.tracking_status) {
                continue;
            }

            match self.reader.read_snapshot() {
                Ok(snapshot) => {
                    let observed = accumulator.observe_snapshot(snapshot);
                    if let Err(error) = save_observed_activity(&self.repository, &observed) {
                        log::warn!("failed to save activity snapshot: {error}");
                    }
                }
                Err(error) => log::warn!("failed to read activity snapshot: {error}"),
            }
        });
    }
}

#[cfg(target_os = "windows")]
impl CollectorService<WindowsActiveWindowReader> {
    pub fn for_windows(
        sample_interval: Duration,
        repository: Arc<Mutex<Repository>>,
        tracking_status: Arc<Mutex<TrackingStatus>>,
    ) -> Self {
        Self::new(
            sample_interval,
            WindowsActiveWindowReader,
            repository,
            tracking_status,
        )
    }
}

struct OpenSession {
    id: String,
    sample: ActivitySample,
    started_at: DateTime<Utc>,
}

struct ObservedActivity {
    sessions: Vec<ActivitySession>,
    primary_session_id: String,
    visible_windows: Vec<WindowObservation>,
}

struct ActivitySessionAccumulator {
    open_session: Option<OpenSession>,
}

impl ActivitySessionAccumulator {
    fn new() -> Self {
        Self { open_session: None }
    }

    fn observe(&mut self, sample: ActivitySample) -> Vec<ActivitySession> {
        let Some(open_session) = self.open_session.as_mut() else {
            let open_session = open_session_from_sample(sample);
            let session = session_from_open(&open_session, open_session.started_at);
            self.open_session = Some(open_session);
            return vec![session];
        };

        if should_merge(&open_session.sample, &sample) {
            open_session.sample = merged_sample(&open_session.sample, &sample);
            let session = session_from_open(open_session, sample.observed_at);
            return vec![session];
        }

        let closed_session = session_from_open(open_session, sample.observed_at);
        let next_open_session = open_session_from_sample(sample);
        let next_session = session_from_open(&next_open_session, next_open_session.started_at);
        self.open_session = Some(next_open_session);

        vec![closed_session, next_session]
    }

    fn observe_snapshot(&mut self, snapshot: ActivitySnapshot) -> ObservedActivity {
        let sessions = self.observe(snapshot.primary);
        let primary_session_id = sessions
            .last()
            .map(|session| session.id.clone())
            .unwrap_or_else(|| format!("active-window:{}", Uuid::new_v4()));

        ObservedActivity {
            sessions,
            primary_session_id,
            visible_windows: snapshot.visible_windows,
        }
    }
}

fn open_session_from_sample(sample: ActivitySample) -> OpenSession {
    OpenSession {
        id: format!("active-window:{}", Uuid::new_v4()),
        started_at: sample.observed_at,
        sample,
    }
}

fn session_from_open(open_session: &OpenSession, ended_at: DateTime<Utc>) -> ActivitySession {
    let ended_at = ended_at.max(open_session.started_at);
    let duration_seconds = (ended_at - open_session.started_at).num_seconds().max(1);

    ActivitySession {
        id: open_session.id.clone(),
        started_at: open_session.started_at,
        ended_at,
        duration_seconds,
        source: if open_session.sample.is_idle {
            ActivitySource::Idle
        } else {
            ActivitySource::ActiveWindow
        },
        app_name: open_session.sample.app_name.clone(),
        process_name: open_session.sample.process_name.clone(),
        window_title: open_session.sample.window_title.clone(),
        domain: open_session.sample.domain.clone(),
        url: None,
        is_idle: open_session.sample.is_idle,
    }
}

fn save_observed_activity(
    repository: &Arc<Mutex<Repository>>,
    observed: &ObservedActivity,
) -> anyhow::Result<()> {
    let repository = repository
        .lock()
        .map_err(|_| anyhow::anyhow!("Repository lock poisoned."))?;

    for session in &observed.sessions {
        let session = enrich_browser_session(&repository, session)?;
        repository.save_session(&session)?;
    }

    repository.save_window_observations(&observed.primary_session_id, &observed.visible_windows)?;

    Ok(())
}

fn enrich_browser_session(
    repository: &Repository,
    session: &ActivitySession,
) -> anyhow::Result<ActivitySession> {
    if session.domain.is_some() || session.is_idle || !is_chromium_browser_session(session) {
        return Ok(session.clone());
    }

    let events = repository.list_recent_browser_events(100)?;
    let Some(event) = choose_browser_event_for_session(session, &events) else {
        return Ok(session.clone());
    };

    let mut enriched = session.clone();
    enriched.source = ActivitySource::BrowserExtension;
    enriched.domain = Some(event.domain.clone());
    Ok(enriched)
}

fn choose_browser_event_for_session<'a>(
    session: &ActivitySession,
    events: &'a [BrowserEvent],
) -> Option<&'a BrowserEvent> {
    events
        .iter()
        .find(|event| {
            browser_event_age_seconds(event, session.ended_at)
                .map(|age| age <= BROWSER_EVENT_MATCHED_TITLE_MAX_AGE_SECONDS)
                .unwrap_or(false)
                && browser_title_matches_window(&session.window_title, &event.title)
        })
        .or_else(|| {
            events.iter().find(|event| {
                browser_event_age_seconds(event, session.ended_at)
                    .map(|age| age <= BROWSER_EVENT_RECENT_FALLBACK_MAX_AGE_SECONDS)
                    .unwrap_or(false)
            })
        })
}

fn browser_event_age_seconds(event: &BrowserEvent, observed_at: DateTime<Utc>) -> Option<i64> {
    let occurred_at = chrono::DateTime::parse_from_rfc3339(&event.occurred_at)
        .ok()?
        .with_timezone(&Utc);
    let age = (observed_at - occurred_at).num_seconds();

    (age >= 0).then_some(age)
}

fn browser_title_matches_window(window_title: &str, tab_title: &str) -> bool {
    let window_title = normalize_browser_title(window_title);
    let tab_title = normalize_browser_title(tab_title);

    !tab_title.is_empty()
        && (window_title.contains(&tab_title) || tab_title.contains(&window_title))
}

fn normalize_browser_title(title: &str) -> String {
    title
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn is_chromium_browser_session(session: &ActivitySession) -> bool {
    let identity = format!("{} {}", session.app_name, session.process_name).to_lowercase();
    [
        "google chrome",
        "chrome.exe",
        "microsoft edge",
        "msedge",
        "brave browser",
        "brave.exe",
        "arc",
        "vivaldi",
        "opera",
    ]
    .iter()
    .any(|browser| identity.contains(browser))
}

fn tracking_is_paused(tracking_status: &Arc<Mutex<TrackingStatus>>) -> bool {
    tracking_status
        .lock()
        .map(|status| status.is_paused())
        .unwrap_or(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::browser_bridge::BrowserEventDraft;
    use chrono::{Duration as ChronoDuration, TimeZone};

    fn sample_at(offset_seconds: i64, app_name: &str, title: &str) -> ActivitySample {
        let observed_at = Utc.with_ymd_and_hms(2026, 6, 18, 9, 0, 0).unwrap()
            + ChronoDuration::seconds(offset_seconds);

        ActivitySample {
            observed_at,
            app_name: app_name.into(),
            process_name: format!("{app_name}.exe"),
            window_title: title.into(),
            domain: None,
            is_idle: false,
        }
    }

    fn observation_for_sample(
        sample: &ActivitySample,
        app_name: &str,
        is_primary: bool,
    ) -> WindowObservation {
        WindowObservation {
            observed_at: sample.observed_at,
            app_name: app_name.into(),
            process_name: format!("{app_name}.app"),
            pid: Some(10),
            bundle_identifier: Some(format!("com.example.{app_name}")),
            window_title: Some(format!("{app_name} title")),
            is_visible: true,
            is_frontmost: is_primary,
            is_primary,
        }
    }

    #[test]
    fn observes_snapshot_primary_without_summing_visible_windows() {
        let mut accumulator = ActivitySessionAccumulator::new();
        let first_sample = sample_at(0, "Safari", "Apple Developer");
        let second_sample = sample_at(10, "Safari", "Apple Developer");
        let first_snapshot = ActivitySnapshot {
            primary: first_sample.clone(),
            visible_windows: vec![
                observation_for_sample(&first_sample, "Safari", true),
                observation_for_sample(&first_sample, "Notes", false),
                observation_for_sample(&first_sample, "Finder", false),
            ],
        };
        let second_snapshot = ActivitySnapshot {
            primary: second_sample.clone(),
            visible_windows: vec![
                observation_for_sample(&second_sample, "Safari", true),
                observation_for_sample(&second_sample, "Notes", false),
                observation_for_sample(&second_sample, "Finder", false),
            ],
        };

        let first = accumulator.observe_snapshot(first_snapshot);
        let second = accumulator.observe_snapshot(second_snapshot);

        assert_eq!(first.sessions.len(), 1);
        assert_eq!(second.sessions.len(), 1);
        assert_eq!(first.sessions[0].duration_seconds, 1);
        assert_eq!(second.sessions[0].duration_seconds, 10);
        assert_eq!(second.primary_session_id, second.sessions[0].id);
        assert_eq!(second.visible_windows.len(), 3);
    }

    #[test]
    fn extends_same_active_window_session_with_stable_id() {
        let mut accumulator = ActivitySessionAccumulator::new();

        let first = accumulator.observe(sample_at(0, "notion", "Project plan"));
        let second = accumulator.observe(sample_at(10, "notion", "Project plan"));

        assert_eq!(first.len(), 1);
        assert_eq!(second.len(), 1);
        assert_eq!(first[0].id, second[0].id);
        assert_eq!(second[0].duration_seconds, 10);
        assert_eq!(second[0].source, ActivitySource::ActiveWindow);
    }

    #[test]
    fn closes_previous_session_when_active_window_changes() {
        let mut accumulator = ActivitySessionAccumulator::new();

        let first = accumulator.observe(sample_at(0, "notion", "Project plan"));
        let switched = accumulator.observe(sample_at(15, "idea64", "FlowPilot"));

        assert_eq!(first.len(), 1);
        assert_eq!(switched.len(), 2);
        assert_eq!(switched[0].id, first[0].id);
        assert_eq!(switched[0].duration_seconds, 15);
        assert_eq!(switched[0].app_name, "notion");
        assert_ne!(switched[1].id, first[0].id);
        assert_eq!(switched[1].app_name, "idea64");
        assert_eq!(switched[1].duration_seconds, 1);
    }

    #[test]
    fn merges_same_app_when_a_generic_fallback_title_flaps() {
        let mut accumulator = ActivitySessionAccumulator::new();

        let first = accumulator.observe(sample_at(0, "Calendar", "Calendar"));
        let second = accumulator.observe(sample_at(5, "Calendar", "Holidays"));
        let third = accumulator.observe(sample_at(10, "Calendar", "Calendar"));

        assert_eq!(first.len(), 1);
        assert_eq!(second.len(), 1);
        assert_eq!(third.len(), 1);
        assert_eq!(first[0].id, second[0].id);
        assert_eq!(second[0].id, third[0].id);
        assert_eq!(third[0].duration_seconds, 10);
        assert_eq!(third[0].window_title, "Holidays");
    }

    #[test]
    fn saves_chromium_browser_sessions_by_recent_tab_domain() {
        let repository = Arc::new(Mutex::new(Repository::in_memory_for_test().expect("repo")));
        repository
            .lock()
            .expect("repo lock")
            .save_browser_event(BrowserEventDraft {
                domain: "github.com".into(),
                url: None,
                title: "GitHub".into(),
            })
            .expect("browser event saved");

        let started_at = Utc::now() + ChronoDuration::seconds(5);
        let session = ActivitySession {
            id: "active-window:chrome".into(),
            started_at,
            ended_at: started_at + ChronoDuration::seconds(10),
            duration_seconds: 10,
            source: ActivitySource::ActiveWindow,
            app_name: "Google Chrome".into(),
            process_name: "Google Chrome".into(),
            window_title: "GitHub - Chrome - Big".into(),
            domain: None,
            url: None,
            is_idle: false,
        };
        let observed = ObservedActivity {
            sessions: vec![session],
            primary_session_id: "active-window:chrome".into(),
            visible_windows: vec![],
        };

        save_observed_activity(&repository, &observed).expect("observed activity saved");

        let saved = repository
            .lock()
            .expect("repo lock")
            .list_sessions_between(
                started_at - ChronoDuration::seconds(1),
                started_at + ChronoDuration::minutes(1),
            )
            .expect("sessions listed");

        assert_eq!(saved.len(), 1);
        assert_eq!(saved[0].domain.as_deref(), Some("github.com"));
        assert_eq!(saved[0].source, ActivitySource::BrowserExtension);
    }
}
