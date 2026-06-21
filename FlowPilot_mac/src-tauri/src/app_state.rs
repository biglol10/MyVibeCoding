use std::sync::{Arc, Mutex};

use chrono::{DateTime, Utc};

use crate::storage::repository::Repository;

#[derive(Debug, Clone)]
pub struct TrackingStatus {
    pub paused_until: Option<DateTime<Utc>>,
}

impl TrackingStatus {
    pub fn is_paused(&self) -> bool {
        self.paused_until
            .map(|until| until > Utc::now())
            .unwrap_or(false)
    }
}

pub struct AppState {
    pub repository: Arc<Mutex<Repository>>,
    pub tracking_status: Arc<Mutex<TrackingStatus>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paused_until_future_counts_as_paused() {
        let status = TrackingStatus {
            paused_until: Some(Utc::now() + chrono::Duration::minutes(15)),
        };
        assert!(status.is_paused());
    }
}
