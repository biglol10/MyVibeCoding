use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::app_state::TrackingStatus;
use crate::collector::active_window::ActiveWindowReader;
#[cfg(target_os = "windows")]
use crate::collector::active_window::WindowsActiveWindowReader;
use crate::collector::session_merger::{should_merge, ActivitySample};
use crate::domain::activity::{ActivitySession, ActivitySource};
use crate::storage::repository::Repository;

pub struct CollectorService<R> {
    reader: R,
    repository: Arc<Mutex<Repository>>,
    pub sample_interval: Duration,
    tracking_status: Arc<Mutex<TrackingStatus>>,
}

impl<R> CollectorService<R>
where
    R: ActiveWindowReader + 'static,
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

            match self.reader.read_open_windows() {
                Ok(samples) => {
                    let sessions = accumulator.observe_many(samples);
                    if let Err(error) = save_sessions(&self.repository, &sessions) {
                        log::warn!("failed to save active window session: {error}");
                    }
                }
                Err(error) => log::warn!("failed to read active window: {error}"),
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

struct ActivitySessionAccumulator {
    open_sessions: BTreeMap<String, OpenSession>,
}

impl ActivitySessionAccumulator {
    fn new() -> Self {
        Self {
            open_sessions: BTreeMap::new(),
        }
    }

    fn observe_many(&mut self, samples: Vec<ActivitySample>) -> Vec<ActivitySession> {
        let observed_at = samples
            .iter()
            .map(|sample| sample.observed_at)
            .max()
            .unwrap_or_else(Utc::now);
        let seen_keys = samples
            .iter()
            .map(|sample| sample.instance_key.clone())
            .collect::<std::collections::BTreeSet<_>>();
        let mut sessions = Vec::new();

        let closed_keys = self
            .open_sessions
            .keys()
            .filter(|key| !seen_keys.contains(*key))
            .cloned()
            .collect::<Vec<_>>();
        for key in closed_keys {
            if let Some(open_session) = self.open_sessions.remove(&key) {
                sessions.push(session_from_open(&open_session, observed_at));
            }
        }

        for sample in samples {
            let key = sample.instance_key.clone();

            match self.open_sessions.remove(&key) {
                Some(open_session) if should_merge(&open_session.sample, &sample) => {
                    let session = session_from_open(&open_session, sample.observed_at);
                    self.open_sessions.insert(key, open_session);
                    sessions.push(session);
                }
                Some(open_session) => {
                    sessions.push(session_from_open(&open_session, sample.observed_at));
                    let next_open_session = open_session_from_sample(sample);
                    sessions.push(session_from_open(
                        &next_open_session,
                        next_open_session.started_at,
                    ));
                    self.open_sessions.insert(key, next_open_session);
                }
                None => {
                    let open_session = open_session_from_sample(sample);
                    sessions.push(session_from_open(&open_session, open_session.started_at));
                    self.open_sessions.insert(key, open_session);
                }
            }
        }

        sessions
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

fn save_sessions(
    repository: &Arc<Mutex<Repository>>,
    sessions: &[ActivitySession],
) -> anyhow::Result<()> {
    let repository = repository
        .lock()
        .map_err(|_| anyhow::anyhow!("Repository lock poisoned."))?;

    for session in sessions {
        repository.save_session(session)?;
    }

    Ok(())
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
    use chrono::{Duration as ChronoDuration, TimeZone};

    fn sample_at(offset_seconds: i64, app_name: &str, title: &str) -> ActivitySample {
        let observed_at = Utc.with_ymd_and_hms(2026, 6, 18, 9, 0, 0).unwrap()
            + ChronoDuration::seconds(offset_seconds);

        ActivitySample {
            observed_at,
            instance_key: format!("window:{app_name}:{title}"),
            app_name: app_name.into(),
            process_name: format!("{app_name}.exe"),
            window_title: title.into(),
            domain: None,
            is_idle: false,
        }
    }

    #[test]
    fn extends_same_active_window_session_with_stable_id() {
        let mut accumulator = ActivitySessionAccumulator::new();

        let first = accumulator.observe_many(vec![sample_at(0, "notion", "Project plan")]);
        let second = accumulator.observe_many(vec![sample_at(10, "notion", "Project plan")]);

        assert_eq!(first.len(), 1);
        assert_eq!(second.len(), 1);
        assert_eq!(first[0].id, second[0].id);
        assert_eq!(second[0].duration_seconds, 10);
        assert_eq!(second[0].source, ActivitySource::ActiveWindow);
    }

    #[test]
    fn closes_previous_session_when_active_window_changes() {
        let mut accumulator = ActivitySessionAccumulator::new();

        let first = accumulator.observe_many(vec![sample_at(0, "notion", "Project plan")]);
        let switched = accumulator.observe_many(vec![sample_at(15, "idea64", "FlowPilot")]);

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
    fn extends_multiple_open_windows_concurrently() {
        let mut accumulator = ActivitySessionAccumulator::new();

        let first = accumulator.observe_many(vec![
            sample_at(0, "notion", "Project plan"),
            sample_at(0, "idea64", "FlowPilot"),
        ]);
        let second = accumulator.observe_many(vec![
            sample_at(10, "notion", "Project plan"),
            sample_at(10, "idea64", "FlowPilot"),
        ]);

        assert_eq!(first.len(), 2);
        assert_eq!(second.len(), 2);
        assert_eq!(second[0].duration_seconds, 10);
        assert_eq!(second[1].duration_seconds, 10);
        assert_eq!(second[0].id, first[0].id);
        assert_eq!(second[1].id, first[1].id);
    }
}
