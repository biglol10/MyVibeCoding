# FlowPilot macOS Collector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add macOS activity collection, macOS permission guidance, preserved Windows collection behavior, Chromium domain bridge reuse, and macOS development/package documentation to FlowPilot.

**Architecture:** Introduce a platform-neutral activity snapshot layer where each sample interval has one primary sample for report totals plus separate visible-window observations for evidence. Keep Windows behavior as a one-primary-sample adapter, add macOS AppKit/CoreGraphics/Accessibility collection behind `#[cfg(target_os = "macos")]`, and expose permission status through a Tauri command consumed by a small Korean React notice.

**Tech Stack:** Tauri 2, React, TypeScript, Vite, Rust, SQLite via `rusqlite`, Windows APIs via `windows`, macOS APIs via `objc2`, `objc2-app-kit`, `objc2-foundation`, `core-foundation`, `core-graphics`, Vitest, React Testing Library, Playwright.

---

## Source Notes

- Approved design: `docs/superpowers/specs/2026-06-19-macos-collector-design.md`
- Apple Accessibility trust API: https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
- Apple Safari Web Extension native app messaging: https://developer.apple.com/documentation/safariservices/messaging-a-web-extension-s-native-app
- Apple Safari Web Extensions overview: https://developer.apple.com/documentation/safariservices/safari-web-extensions
- Tauri macOS code signing: https://v2.tauri.app/distribute/sign/macos/
- Tauri distribution overview: https://v2.tauri.app/distribute/
- `objc2` crate: https://docs.rs/objc2
- `core-graphics` crate: https://docs.rs/crate/core-graphics/latest

## File Structure

- Modify `src-tauri/Cargo.toml`: add macOS-only dependencies without touching Windows-only dependency gating.
- Modify `src-tauri/src/collector/mod.rs`: expose the new snapshot module and macOS module behind cfg.
- Create `src-tauri/src/collector/snapshot.rs`: shared `ActivitySnapshot`, `WindowObservation`, `ActivitySnapshotReader`, and pure primary-selection helpers.
- Modify `src-tauri/src/collector/active_window.rs`: keep Windows API code, but implement `ActivitySnapshotReader` instead of the old active-window reader trait.
- Modify `src-tauri/src/collector/service.rs`: read snapshots, merge only the primary sample, and persist visible-window evidence separately.
- Create `src-tauri/src/collector/macos.rs`: macOS AppKit/CoreGraphics/Accessibility reader.
- Modify `src-tauri/src/storage/schema.rs`: add the `window_observations` table and indexes.
- Modify `src-tauri/src/storage/repository.rs`: add evidence persistence and tests.
- Create `src-tauri/src/permissions.rs`: cross-platform permission status DTO plus macOS permission checks.
- Modify `src-tauri/src/lib.rs`: register the permission command and start the macOS collector.
- Modify `src/types/activity.ts`: add permission status DTO type.
- Modify `src/api/activityApi.ts`: add typed permission-status wrapper plus dev fallback.
- Create `src/components/platform/MacosPermissionNotice.tsx`: Korean macOS permission notice.
- Create `src/components/platform/MacosPermissionNotice.test.tsx`: notice rendering tests.
- Modify `src/App.tsx`: load permission status and render the notice above page content.
- Modify `src/App.test.tsx`: keep app smoke coverage stable with the new async permission call.
- Modify `src/styles.css`: add compact notice styling.
- Create `docs/macos-development.md`: development, packaging, signing, notarization, Safari extension notes.

## Task 1: Prepare Dependencies and Baseline

**Files:**
- Modify: `src-tauri/Cargo.toml`
- Verify only: root `package.json`, `browser-extension/package.json`

- [ ] **Step 1: Confirm the working copy is clean**

Run:

```bash
git status --short --branch
```

Expected: branch is `main` and no tracked files are modified except files created by earlier documentation commits.

- [ ] **Step 2: Install Node dependencies**

Run:

```bash
npm install
npm install --prefix browser-extension
```

Expected: root and browser-extension `node_modules` directories are created, and package-lock files remain compatible with the committed manifests.

- [ ] **Step 3: Expose Rust toolchain**

Run:

```bash
which cargo rustc || true
```

Expected if already installed: both commands print paths.

If not installed, install Rust with:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustc --version
cargo --version
```

Expected: `rustc --version` and `cargo --version` print versions that satisfy `src-tauri/Cargo.toml`'s `rust-version = "1.77.2"`.

- [ ] **Step 4: Add macOS-only Rust dependencies**

Modify `src-tauri/Cargo.toml` by adding this block below the Windows dependency block:

```toml
[target.'cfg(target_os = "macos")'.dependencies]
core-foundation = "0.10"
core-graphics = { version = "0.25", features = ["link"] }
objc2 = "0.6.4"
objc2-app-kit = { version = "0.3.2", features = ["NSRunningApplication", "NSWorkspace"] }
objc2-foundation = { version = "0.3.2", features = ["NSArray", "NSString"] }
```

- [ ] **Step 5: Run baseline tests before production code changes**

Run:

```bash
npm test
npm test --prefix browser-extension
cargo test --manifest-path src-tauri/Cargo.toml
```

Expected: frontend, extension, and Rust tests pass. If a baseline failure appears, record the failure before changing production code.

- [ ] **Step 6: Commit dependency/setup changes**

Run:

```bash
git add src-tauri/Cargo.toml src-tauri/Cargo.lock package-lock.json browser-extension/package-lock.json
git commit -m "chore: prepare macos collector dependencies"
```

Expected: commit succeeds. If lockfiles did not change, omit them from `git add`.

## Task 2: Add Shared Snapshot Model

**Files:**
- Create: `src-tauri/src/collector/snapshot.rs`
- Modify: `src-tauri/src/collector/mod.rs`
- Test: `src-tauri/src/collector/snapshot.rs`

- [ ] **Step 1: Write failing snapshot tests**

Create `src-tauri/src/collector/snapshot.rs` with the tests first:

```rust
use chrono::{DateTime, Utc};

use crate::collector::session_merger::ActivitySample;

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
        assert_eq!(snapshot.visible_windows[0].window_title.as_deref(), Some("Apple Developer"));
    }

    #[test]
    fn chooses_frontmost_non_flowpilot_window_as_primary() {
        let flowpilot = observation("FlowPilot", true, false);
        let code = observation("Code", true, false);
        let finder = observation("Finder", false, false);

        let selected = choose_primary_observation(
            &[flowpilot, finder, code],
            Some("com.example.FlowPilot"),
        )
        .expect("primary observation");

        assert_eq!(selected.app_name, "Code");
    }

    #[test]
    fn falls_back_to_first_visible_non_flowpilot_window() {
        let flowpilot = observation("FlowPilot", false, false);
        let notes = observation("Notes", false, false);

        let selected = choose_primary_observation(
            &[flowpilot, notes],
            Some("com.example.FlowPilot"),
        )
        .expect("fallback observation");

        assert_eq!(selected.app_name, "Notes");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml collector::snapshot -- --nocapture
```

Expected: FAIL because `WindowObservation`, `ActivitySnapshot`, and `choose_primary_observation` are not defined.

- [ ] **Step 3: Implement snapshot model**

Replace the top of `src-tauri/src/collector/snapshot.rs` above the tests with:

```rust
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
        .find(|observation| observation.is_frontmost && !is_own_app(observation, own_bundle_identifier))
        .or_else(|| {
            observations
                .iter()
                .find(|observation| observation.is_visible && !is_own_app(observation, own_bundle_identifier))
        })
        .or_else(|| observations.iter().find(|observation| observation.is_frontmost))
        .or_else(|| observations.iter().find(|observation| observation.is_visible))
}

fn is_own_app(observation: &WindowObservation, own_bundle_identifier: Option<&str>) -> bool {
    own_bundle_identifier
        .and_then(|own| observation.bundle_identifier.as_deref().map(|bundle| bundle == own))
        .unwrap_or(false)
        || observation.app_name.eq_ignore_ascii_case("FlowPilot")
}
```

- [ ] **Step 4: Export the module**

Modify `src-tauri/src/collector/mod.rs`:

```rust
pub mod active_window;
pub mod idle;
#[cfg(target_os = "macos")]
pub mod macos;
pub mod service;
pub mod session_merger;
pub mod snapshot;
```

- [ ] **Step 5: Run test to verify it passes**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml collector::snapshot -- --nocapture
```

Expected: PASS for the snapshot tests.

- [ ] **Step 6: Commit**

Run:

```bash
git add src-tauri/src/collector/mod.rs src-tauri/src/collector/snapshot.rs
git commit -m "feat: add activity snapshot model"
```

## Task 3: Persist Visible Window Evidence

**Files:**
- Modify: `src-tauri/src/storage/schema.rs`
- Modify: `src-tauri/src/storage/repository.rs`
- Test: `src-tauri/src/storage/schema.rs`, `src-tauri/src/storage/repository.rs`

- [ ] **Step 1: Write failing schema test**

Add this test to `src-tauri/src/storage/schema.rs`:

```rust
#[test]
fn creates_window_observation_table_and_indexes() {
    let conn = Connection::open_in_memory().expect("in-memory db");
    initialize_schema(&conn).expect("schema initialized");

    let table_exists: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='window_observations'",
            [],
            |row| row.get(0),
        )
        .expect("table count");

    assert_eq!(table_exists, 1);

    for index_name in [
        "idx_window_observations_observed_at",
        "idx_window_observations_session_id",
    ] {
        let exists: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name=?1",
                [index_name],
                |row| row.get(0),
            )
            .expect("index count");

        assert_eq!(exists, 1, "{index_name} should exist");
    }
}
```

- [ ] **Step 2: Run schema test to verify it fails**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml storage::schema::tests::creates_window_observation_table_and_indexes -- --nocapture
```

Expected: FAIL because the table and indexes do not exist.

- [ ] **Step 3: Add schema**

In `initialize_schema`, add this SQL before the index block:

```sql
        CREATE TABLE IF NOT EXISTS window_observations (
          id TEXT PRIMARY KEY,
          session_id TEXT,
          observed_at TEXT NOT NULL,
          app_name TEXT NOT NULL,
          process_name TEXT NOT NULL,
          pid INTEGER,
          bundle_identifier TEXT,
          window_title TEXT,
          is_visible INTEGER NOT NULL DEFAULT 0,
          is_frontmost INTEGER NOT NULL DEFAULT 0,
          is_primary INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY(session_id) REFERENCES activity_sessions(id) ON DELETE SET NULL
        );
```

Add these indexes inside the existing index block:

```sql
        CREATE INDEX IF NOT EXISTS idx_window_observations_observed_at ON window_observations(observed_at);
        CREATE INDEX IF NOT EXISTS idx_window_observations_session_id ON window_observations(session_id);
```

- [ ] **Step 4: Run schema test to verify it passes**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml storage::schema::tests::creates_window_observation_table_and_indexes -- --nocapture
```

Expected: PASS.

- [ ] **Step 5: Write failing repository test**

In `src-tauri/src/storage/repository.rs`, import the observation type:

```rust
use crate::collector::snapshot::WindowObservation;
```

Add this test to the repository test module:

```rust
#[test]
fn saves_window_observations_without_changing_activity_sessions() {
    let repo = Repository::in_memory_for_test().expect("repo");
    let started_at = Utc::now();
    let session = test_session("session-with-windows", started_at);
    repo.save_session(&session).expect("session saved");

    let observations = vec![
        WindowObservation {
            observed_at: started_at,
            app_name: "Safari".into(),
            process_name: "Safari".into(),
            pid: Some(100),
            bundle_identifier: Some("com.apple.Safari".into()),
            window_title: Some("Developer Documentation".into()),
            is_visible: true,
            is_frontmost: true,
            is_primary: true,
        },
        WindowObservation {
            observed_at: started_at,
            app_name: "Notes".into(),
            process_name: "Notes".into(),
            pid: Some(101),
            bundle_identifier: Some("com.apple.Notes".into()),
            window_title: Some("Meeting notes".into()),
            is_visible: true,
            is_frontmost: false,
            is_primary: false,
        },
    ];

    repo.save_window_observations(&session.id, &observations)
        .expect("observations saved");

    let observation_count: i64 = repo
        .conn
        .query_row("SELECT COUNT(*) FROM window_observations", [], |row| row.get(0))
        .expect("observation count");
    let session_count: i64 = repo
        .conn
        .query_row("SELECT COUNT(*) FROM activity_sessions", [], |row| row.get(0))
        .expect("session count");
    let primary_count: i64 = repo
        .conn
        .query_row(
            "SELECT COUNT(*) FROM window_observations WHERE is_primary=1 AND session_id=?1",
            [&session.id],
            |row| row.get(0),
        )
        .expect("primary count");

    assert_eq!(observation_count, 2);
    assert_eq!(session_count, 1);
    assert_eq!(primary_count, 1);
}
```

- [ ] **Step 6: Run repository test to verify it fails**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml storage::repository::tests::saves_window_observations_without_changing_activity_sessions -- --nocapture
```

Expected: FAIL because `save_window_observations` is not implemented.

- [ ] **Step 7: Implement repository method**

Add this method to `impl Repository`:

```rust
pub fn save_window_observations(
    &self,
    session_id: &str,
    observations: &[WindowObservation],
) -> rusqlite::Result<()> {
    let now = Utc::now().to_rfc3339();

    for observation in observations {
        self.conn.execute(
            r#"
            INSERT INTO window_observations (
              id, session_id, observed_at, app_name, process_name, pid, bundle_identifier,
              window_title, is_visible, is_frontmost, is_primary, created_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
            "#,
            params![
                Uuid::new_v4().to_string(),
                session_id,
                observation.observed_at.to_rfc3339(),
                &observation.app_name,
                &observation.process_name,
                observation.pid.map(i64::from),
                observation.bundle_identifier.as_deref(),
                observation.window_title.as_deref(),
                bool_to_db(observation.is_visible),
                bool_to_db(observation.is_frontmost),
                bool_to_db(observation.is_primary),
                &now,
            ],
        )?;
    }

    Ok(())
}
```

- [ ] **Step 8: Run repository and schema tests**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml storage:: -- --nocapture
```

Expected: PASS for storage tests.

- [ ] **Step 9: Commit**

Run:

```bash
git add src-tauri/src/storage/schema.rs src-tauri/src/storage/repository.rs
git commit -m "feat: persist window observations"
```

## Task 4: Refactor Collector Service to Read Snapshots

**Files:**
- Modify: `src-tauri/src/collector/service.rs`
- Test: `src-tauri/src/collector/service.rs`

- [ ] **Step 1: Write failing service test for multi-window snapshots**

In `src-tauri/src/collector/service.rs`, update the test module imports to include:

```rust
use crate::collector::snapshot::{ActivitySnapshot, WindowObservation};
```

Add this helper in the test module:

```rust
fn observation_for_sample(sample: &ActivitySample, app_name: &str, is_primary: bool) -> WindowObservation {
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
```

Add this test:

```rust
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml collector::service::tests::observes_snapshot_primary_without_summing_visible_windows -- --nocapture
```

Expected: FAIL because `observe_snapshot` and its return type are not implemented.

- [ ] **Step 3: Update service to use snapshots**

In `src-tauri/src/collector/service.rs`, replace imports:

```rust
use crate::collector::active_window::ActiveWindowReader;
```

with:

```rust
use crate::collector::snapshot::{ActivitySnapshot, ActivitySnapshotReader};
```

Change the generic bound:

```rust
R: ActivitySnapshotReader + 'static,
```

Change the collector loop body:

```rust
match self.reader.read_snapshot() {
    Ok(snapshot) => {
        let observed = accumulator.observe_snapshot(snapshot);
        if let Err(error) = save_observed_activity(&self.repository, &observed) {
            log::warn!("failed to save activity snapshot: {error}");
        }
    }
    Err(error) => log::warn!("failed to read activity snapshot: {error}"),
}
```

Add this struct near `OpenSession`:

```rust
struct ObservedActivity {
    sessions: Vec<ActivitySession>,
    primary_session_id: String,
    visible_windows: Vec<crate::collector::snapshot::WindowObservation>,
}
```

Add this method:

```rust
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
```

Replace `save_sessions` with:

```rust
fn save_observed_activity(
    repository: &Arc<Mutex<Repository>>,
    observed: &ObservedActivity,
) -> anyhow::Result<()> {
    let repository = repository
        .lock()
        .map_err(|_| anyhow::anyhow!("Repository lock poisoned."))?;

    for session in &observed.sessions {
        repository.save_session(session)?;
    }

    repository.save_window_observations(&observed.primary_session_id, &observed.visible_windows)?;

    Ok(())
}
```

- [ ] **Step 4: Preserve existing service tests**

Update existing service tests that call `accumulator.observe(sample)` only if compiler privacy requires it. Keep `observe` private and allow tests in the same module to use both `observe` and `observe_snapshot`.

- [ ] **Step 5: Run service tests**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml collector::service -- --nocapture
```

Expected: PASS for existing and new service tests.

- [ ] **Step 6: Commit**

Run:

```bash
git add src-tauri/src/collector/service.rs
git commit -m "feat: collect activity snapshots"
```

## Task 5: Adapt Windows Reader Without Behavior Change

**Files:**
- Modify: `src-tauri/src/collector/active_window.rs`
- Test: `src-tauri/src/collector/active_window.rs`, `src-tauri/src/collector/service.rs`

- [ ] **Step 1: Write failing adapter test**

Add this non-Windows-specific helper and test to `src-tauri/src/collector/active_window.rs`:

```rust
fn snapshot_from_active_window_sample(sample: ActivitySample) -> crate::collector::snapshot::ActivitySnapshot {
    crate::collector::snapshot::ActivitySnapshot::from_primary(sample)
}

#[cfg(test)]
mod snapshot_tests {
    use super::*;
    use chrono::Utc;

    #[test]
    fn active_window_snapshot_contains_only_primary_observation() {
        let sample = ActivitySample {
            observed_at: Utc::now(),
            app_name: "Code".into(),
            process_name: "Code.exe".into(),
            window_title: "FlowPilot".into(),
            domain: None,
            is_idle: false,
        };

        let snapshot = snapshot_from_active_window_sample(sample.clone());

        assert_eq!(snapshot.primary, sample);
        assert_eq!(snapshot.visible_windows.len(), 1);
        assert!(snapshot.visible_windows[0].is_primary);
    }
}
```

- [ ] **Step 2: Run adapter test to verify it fails**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml collector::active_window::snapshot_tests -- --nocapture
```

Expected: FAIL if imports or snapshot module references are not wired.

- [ ] **Step 3: Replace Windows trait implementation**

In `src-tauri/src/collector/active_window.rs`, remove the old trait:

```rust
pub trait ActiveWindowReader: Send + Sync {
    fn read_active_window(&self) -> anyhow::Result<ActivitySample>;
}
```

Add:

```rust
use crate::collector::snapshot::{ActivitySnapshot, ActivitySnapshotReader};
```

Change the Windows impl signature:

```rust
impl ActivitySnapshotReader for WindowsActiveWindowReader {
    fn read_snapshot(&self) -> anyhow::Result<ActivitySnapshot> {
```

At the end of the Windows method, return:

```rust
Ok(snapshot_from_active_window_sample(ActivitySample {
    observed_at: Utc::now(),
    app_name: process_name.clone(),
    process_name,
    window_title,
    domain: None,
    is_idle: false,
}))
```

- [ ] **Step 4: Run Windows adapter and service tests**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml collector::active_window collector::service -- --nocapture
```

Expected: PASS on macOS for non-Windows tests. On Windows, the existing Windows basename test also passes.

- [ ] **Step 5: Commit**

Run:

```bash
git add src-tauri/src/collector/active_window.rs src-tauri/src/collector/service.rs
git commit -m "refactor: adapt windows collector to snapshots"
```

## Task 6: Add macOS Collector

**Files:**
- Create: `src-tauri/src/collector/macos.rs`
- Modify: `src-tauri/src/lib.rs`
- Test: `src-tauri/src/collector/snapshot.rs`, `src-tauri/src/collector/macos.rs`

- [ ] **Step 1: Write failing macOS mapping tests**

Create `src-tauri/src/collector/macos.rs` with pure tests first:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn sample_from_observation_preserves_app_process_and_title() {
        let observed_at = chrono::Utc.with_ymd_and_hms(2026, 6, 19, 9, 0, 0).unwrap();
        let observation = crate::collector::snapshot::WindowObservation {
            observed_at,
            app_name: "Safari".into(),
            process_name: "Safari".into(),
            pid: Some(123),
            bundle_identifier: Some("com.apple.Safari".into()),
            window_title: Some("Apple Developer".into()),
            is_visible: true,
            is_frontmost: true,
            is_primary: true,
        };

        let sample = sample_from_observation(&observation);

        assert_eq!(sample.app_name, "Safari");
        assert_eq!(sample.process_name, "Safari");
        assert_eq!(sample.window_title, "Apple Developer");
        assert_eq!(sample.domain, None);
        assert!(!sample.is_idle);
    }

    #[test]
    fn sample_from_observation_uses_app_name_when_title_is_missing() {
        let observed_at = chrono::Utc.with_ymd_and_hms(2026, 6, 19, 9, 0, 0).unwrap();
        let observation = crate::collector::snapshot::WindowObservation {
            observed_at,
            app_name: "Notes".into(),
            process_name: "Notes".into(),
            pid: None,
            bundle_identifier: None,
            window_title: None,
            is_visible: true,
            is_frontmost: true,
            is_primary: true,
        };

        let sample = sample_from_observation(&observation);

        assert_eq!(sample.window_title, "Notes");
    }
}
```

- [ ] **Step 2: Run macOS mapping tests to verify failure**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml collector::macos -- --nocapture
```

Expected: FAIL because `sample_from_observation` is not implemented.

- [ ] **Step 3: Implement pure mapping and reader skeleton**

Add this top-level code above the tests in `src-tauri/src/collector/macos.rs`:

```rust
use anyhow::{anyhow, Context};
use chrono::Utc;

use crate::collector::session_merger::ActivitySample;
use crate::collector::snapshot::{
    choose_primary_observation, ActivitySnapshot, ActivitySnapshotReader, WindowObservation,
};

pub struct MacosActivitySnapshotReader {
    own_bundle_identifier: Option<String>,
}

impl MacosActivitySnapshotReader {
    pub fn new() -> Self {
        Self {
            own_bundle_identifier: Some("app.flowpilot.desktop".into()),
        }
    }
}

impl ActivitySnapshotReader for MacosActivitySnapshotReader {
    fn read_snapshot(&self) -> anyhow::Result<ActivitySnapshot> {
        let mut observations = collect_window_observations().context("macOS window collection failed")?;
        let primary_index = choose_primary_observation(&observations, self.own_bundle_identifier.as_deref())
            .and_then(|selected| observations.iter().position(|observation| observation == selected))
            .ok_or_else(|| anyhow!("no macOS activity observation is available"))?;

        for (index, observation) in observations.iter_mut().enumerate() {
            observation.is_primary = index == primary_index;
        }

        let primary = sample_from_observation(&observations[primary_index]);

        Ok(ActivitySnapshot {
            primary,
            visible_windows: observations,
        })
    }
}

fn sample_from_observation(observation: &WindowObservation) -> ActivitySample {
    ActivitySample {
        observed_at: observation.observed_at,
        app_name: observation.app_name.clone(),
        process_name: observation.process_name.clone(),
        window_title: observation
            .window_title
            .clone()
            .filter(|title| !title.trim().is_empty())
            .unwrap_or_else(|| observation.app_name.clone()),
        domain: None,
        is_idle: false,
    }
}
```

- [ ] **Step 4: Implement macOS collection**

Add a cfg-macos implementation for `collect_window_observations` using AppKit and CoreGraphics. Keep all Objective-C/CoreFoundation work in this file.

Required behavior:

```rust
#[cfg(target_os = "macos")]
fn collect_window_observations() -> anyhow::Result<Vec<WindowObservation>> {
    let observed_at = Utc::now();
    let running_apps = running_app_observations(observed_at)?;
    let window_rows = core_graphics_window_rows()?;

    Ok(merge_running_apps_and_windows(observed_at, running_apps, window_rows))
}

#[cfg(not(target_os = "macos"))]
fn collect_window_observations() -> anyhow::Result<Vec<WindowObservation>> {
    Err(anyhow!("macOS activity collection is only available on macOS"))
}
```

Implementation notes:

- `running_app_observations` should use `objc2_app_kit::NSWorkspace::sharedWorkspace()` and `runningApplications()`.
- It should read localized name, bundle identifier, process identifier, and active/frontmost state when available.
- `core_graphics_window_rows` should use CoreGraphics window-list APIs to get on-screen windows and owner process identifiers.
- `merge_running_apps_and_windows` should join rows by pid, preserve the best available title, mark visible rows as `is_visible = true`, and include running frontmost apps even when window title access is denied.
- The code must not capture or store screenshots.

- [ ] **Step 5: Wire macOS collector startup**

Modify `src-tauri/src/lib.rs` setup after the Windows collector block:

```rust
#[cfg(target_os = "macos")]
collector::service::CollectorService::new(
    Duration::from_secs(5),
    collector::macos::MacosActivitySnapshotReader::new(),
    repository.clone(),
    tracking_status.clone(),
)
.start();
```

- [ ] **Step 6: Run macOS collector tests**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml collector::macos collector::snapshot -- --nocapture
```

Expected: PASS. If Objective-C crate API names differ from the code notes, adjust the macOS implementation while preserving the tested pure mapping behavior.

- [ ] **Step 7: Commit**

Run:

```bash
git add src-tauri/src/collector/macos.rs src-tauri/src/lib.rs src-tauri/Cargo.toml src-tauri/Cargo.lock
git commit -m "feat: add macos activity collector"
```

## Task 7: Add Permission Status Command

**Files:**
- Create: `src-tauri/src/permissions.rs`
- Modify: `src-tauri/src/lib.rs`
- Test: `src-tauri/src/permissions.rs`

- [ ] **Step 1: Write failing permission serialization tests**

Create `src-tauri/src/permissions.rs` with tests first:

```rust
use serde::Serialize;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn permission_status_serializes_with_camel_case_fields() {
        let status = PlatformPermissionStatus {
            platform: "macos".into(),
            accessibility_granted: false,
            screen_recording_granted: true,
            accessibility_required_reason: "앱과 창 제목을 정확히 기록하려면 손쉬운 사용 권한이 필요합니다.".into(),
            screen_recording_required_reason: "열려 있는 창 목록과 제목을 확인하려면 화면 기록 권한이 필요할 수 있습니다.".into(),
            can_prompt_accessibility: true,
            can_prompt_screen_recording: true,
        };

        let serialized = serde_json::to_value(status).expect("serialized");

        assert_eq!(serialized["accessibilityGranted"], false);
        assert_eq!(serialized["screenRecordingGranted"], true);
        assert_eq!(serialized["canPromptAccessibility"], true);
        assert!(serialized["accessibility_required_reason"].is_null());
    }
}
```

- [ ] **Step 2: Run permission test to verify it fails**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml permissions -- --nocapture
```

Expected: FAIL because the module is not exported and `PlatformPermissionStatus` is missing.

- [ ] **Step 3: Implement permission DTO and command**

Replace `src-tauri/src/permissions.rs` with:

```rust
use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlatformPermissionStatus {
    pub platform: String,
    pub accessibility_granted: bool,
    pub screen_recording_granted: bool,
    pub accessibility_required_reason: String,
    pub screen_recording_required_reason: String,
    pub can_prompt_accessibility: bool,
    pub can_prompt_screen_recording: bool,
}

#[tauri::command]
pub fn get_platform_permission_status() -> PlatformPermissionStatus {
    platform_permission_status()
}

pub fn platform_permission_status() -> PlatformPermissionStatus {
    PlatformPermissionStatus {
        platform: platform_name().into(),
        accessibility_granted: accessibility_granted(),
        screen_recording_granted: screen_recording_granted(),
        accessibility_required_reason: "앱과 창 제목을 정확히 기록하려면 손쉬운 사용 권한이 필요합니다.".into(),
        screen_recording_required_reason:
            "열려 있는 창 목록과 제목을 확인하려면 화면 기록 권한이 필요할 수 있습니다. FlowPilot은 화면 이미지를 저장하지 않습니다.".into(),
        can_prompt_accessibility: cfg!(target_os = "macos"),
        can_prompt_screen_recording: cfg!(target_os = "macos"),
    }
}

fn platform_name() -> &'static str {
    if cfg!(target_os = "macos") {
        "macos"
    } else if cfg!(target_os = "windows") {
        "windows"
    } else {
        "other"
    }
}

#[cfg(target_os = "macos")]
fn accessibility_granted() -> bool {
    extern "C" {
        fn AXIsProcessTrusted() -> bool;
    }

    unsafe { AXIsProcessTrusted() }
}

#[cfg(not(target_os = "macos"))]
fn accessibility_granted() -> bool {
    true
}

#[cfg(target_os = "macos")]
fn screen_recording_granted() -> bool {
    core_graphics::access::ScreenCaptureAccess::default().preflight()
}

#[cfg(not(target_os = "macos"))]
fn screen_recording_granted() -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn permission_status_serializes_with_camel_case_fields() {
        let status = PlatformPermissionStatus {
            platform: "macos".into(),
            accessibility_granted: false,
            screen_recording_granted: true,
            accessibility_required_reason: "앱과 창 제목을 정확히 기록하려면 손쉬운 사용 권한이 필요합니다.".into(),
            screen_recording_required_reason: "열려 있는 창 목록과 제목을 확인하려면 화면 기록 권한이 필요할 수 있습니다.".into(),
            can_prompt_accessibility: true,
            can_prompt_screen_recording: true,
        };

        let serialized = serde_json::to_value(status).expect("serialized");

        assert_eq!(serialized["accessibilityGranted"], false);
        assert_eq!(serialized["screenRecordingGranted"], true);
        assert_eq!(serialized["canPromptAccessibility"], true);
        assert!(serialized["accessibility_required_reason"].is_null());
    }
}
```

- [ ] **Step 4: Export and register the command**

Modify `src-tauri/src/lib.rs`:

```rust
pub mod permissions;
```

Add to `tauri::generate_handler!`:

```rust
permissions::get_platform_permission_status,
```

- [ ] **Step 5: Run permission tests**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml permissions -- --nocapture
```

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git add src-tauri/src/permissions.rs src-tauri/src/lib.rs
git commit -m "feat: expose platform permission status"
```

## Task 8: Add Korean macOS Permission Notice

**Files:**
- Modify: `src/types/activity.ts`
- Modify: `src/api/activityApi.ts`
- Create: `src/components/platform/MacosPermissionNotice.tsx`
- Create: `src/components/platform/MacosPermissionNotice.test.tsx`
- Modify: `src/App.tsx`
- Modify: `src/App.test.tsx`
- Modify: `src/styles.css`

- [ ] **Step 1: Write failing notice tests**

Create `src/components/platform/MacosPermissionNotice.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { MacosPermissionNotice } from "./MacosPermissionNotice";
import type { PlatformPermissionStatus } from "../../types/activity";

function status(overrides: Partial<PlatformPermissionStatus> = {}): PlatformPermissionStatus {
  return {
    platform: "macos",
    accessibilityGranted: false,
    screenRecordingGranted: false,
    accessibilityRequiredReason: "앱과 창 제목을 정확히 기록하려면 손쉬운 사용 권한이 필요합니다.",
    screenRecordingRequiredReason: "열려 있는 창 목록과 제목을 확인하려면 화면 기록 권한이 필요할 수 있습니다. FlowPilot은 화면 이미지를 저장하지 않습니다.",
    canPromptAccessibility: true,
    canPromptScreenRecording: true,
    ...overrides,
  };
}

describe("MacosPermissionNotice", () => {
  it("renders Korean guidance when macOS permissions are missing", () => {
    render(<MacosPermissionNotice permissionStatus={status()} />);

    expect(screen.getByText("macOS 권한 설정이 필요합니다")).toBeInTheDocument();
    expect(screen.getByText(/손쉬운 사용 권한/)).toBeInTheDocument();
    expect(screen.getByText(/화면 기록 권한/)).toBeInTheDocument();
    expect(screen.getByText(/FlowPilot을 허용한 뒤 앱을 다시 실행/)).toBeInTheDocument();
  });

  it("does not render outside macOS", () => {
    const { container } = render(<MacosPermissionNotice permissionStatus={status({ platform: "windows" })} />);

    expect(container).toBeEmptyDOMElement();
  });

  it("does not render when both permissions are granted", () => {
    const { container } = render(
      <MacosPermissionNotice permissionStatus={status({ accessibilityGranted: true, screenRecordingGranted: true })} />,
    );

    expect(container).toBeEmptyDOMElement();
  });
});
```

- [ ] **Step 2: Run notice tests to verify they fail**

Run:

```bash
npm test -- src/components/platform/MacosPermissionNotice.test.tsx
```

Expected: FAIL because the component and type do not exist.

- [ ] **Step 3: Add frontend permission type**

Add to `src/types/activity.ts`:

```ts
export interface PlatformPermissionStatus {
  platform: "macos" | "windows" | "other";
  accessibilityGranted: boolean;
  screenRecordingGranted: boolean;
  accessibilityRequiredReason: string;
  screenRecordingRequiredReason: string;
  canPromptAccessibility: boolean;
  canPromptScreenRecording: boolean;
}
```

- [ ] **Step 4: Add API wrapper**

Update the import in `src/api/activityApi.ts`:

```ts
import type {
  ActivitySession,
  ClassificationRule,
  PlatformPermissionStatus,
  RuleDraft,
  TodaySummary,
} from "../types/activity";
```

Add:

```ts
export async function getPlatformPermissionStatus(): Promise<PlatformPermissionStatus> {
  if (!isDesktopRuntime()) {
    return {
      platform: "other",
      accessibilityGranted: true,
      screenRecordingGranted: true,
      accessibilityRequiredReason: "",
      screenRecordingRequiredReason: "",
      canPromptAccessibility: false,
      canPromptScreenRecording: false,
    };
  }

  return invoke<PlatformPermissionStatus>("get_platform_permission_status");
}
```

- [ ] **Step 5: Implement notice component**

Create `src/components/platform/MacosPermissionNotice.tsx`:

```tsx
import type { PlatformPermissionStatus } from "../../types/activity";

interface MacosPermissionNoticeProps {
  permissionStatus: PlatformPermissionStatus | null;
}

export function MacosPermissionNotice({ permissionStatus }: MacosPermissionNoticeProps) {
  if (!permissionStatus || permissionStatus.platform !== "macos") {
    return null;
  }

  const missingAccessibility = !permissionStatus.accessibilityGranted;
  const missingScreenRecording = !permissionStatus.screenRecordingGranted;

  if (!missingAccessibility && !missingScreenRecording) {
    return null;
  }

  return (
    <section className="permission-notice" aria-labelledby="macos-permission-title">
      <div>
        <h2 id="macos-permission-title">macOS 권한 설정이 필요합니다</h2>
        <p>시스템 설정 &gt; 개인정보 보호 및 보안에서 FlowPilot을 허용한 뒤 앱을 다시 실행해 주세요.</p>
      </div>
      <ul>
        {missingAccessibility ? <li>{permissionStatus.accessibilityRequiredReason}</li> : null}
        {missingScreenRecording ? <li>{permissionStatus.screenRecordingRequiredReason}</li> : null}
      </ul>
    </section>
  );
}
```

- [ ] **Step 6: Add styles**

Add to `src/styles.css`:

```css
.permission-notice {
  display: grid;
  gap: 12px;
  padding: 16px 18px;
  border: 1px solid #f59e0b;
  border-radius: 8px;
  background: #fffbeb;
  color: #78350f;
}

.permission-notice h2 {
  margin: 0;
  font-size: 1rem;
}

.permission-notice p,
.permission-notice ul {
  margin: 0;
}

.permission-notice ul {
  padding-left: 20px;
}
```

- [ ] **Step 7: Render notice in App**

In `src/App.tsx`, update imports:

```tsx
import { getPlatformPermissionStatus, getTodaySessions, getTodaySummary } from "./api/activityApi";
import { MacosPermissionNotice } from "./components/platform/MacosPermissionNotice";
import type { ActivitySession, PlatformPermissionStatus, TodaySummary as TodaySummaryDto } from "./types/activity";
```

Add state:

```tsx
const [permissionStatus, setPermissionStatus] = useState<PlatformPermissionStatus | null>(null);
```

Add effect:

```tsx
useEffect(() => {
  let isMounted = true;

  getPlatformPermissionStatus()
    .then((status) => {
      if (isMounted) {
        setPermissionStatus(status);
      }
    })
    .catch(() => {
      if (isMounted) {
        setPermissionStatus(null);
      }
    });

  return () => {
    isMounted = false;
  };
}, []);
```

Render before loading/error/ready panels:

```tsx
<MacosPermissionNotice permissionStatus={permissionStatus} />
```

- [ ] **Step 8: Run notice tests**

Run:

```bash
npm test -- src/components/platform/MacosPermissionNotice.test.tsx src/App.test.tsx
```

Expected: PASS.

- [ ] **Step 9: Commit**

Run:

```bash
git add src/types/activity.ts src/api/activityApi.ts src/components/platform/MacosPermissionNotice.tsx src/components/platform/MacosPermissionNotice.test.tsx src/App.tsx src/App.test.tsx src/styles.css
git commit -m "feat: show macos permission guidance"
```

## Task 9: Document macOS Development and Packaging

**Files:**
- Create: `docs/macos-development.md`

- [ ] **Step 1: Write the macOS documentation**

Create `docs/macos-development.md`:

```markdown
# FlowPilot macOS Development and Packaging

## Development Run

From `/Users/biglol/Desktop/practice/FlowPilot_mac`:

```bash
npm install
npm install --prefix browser-extension
source "$HOME/.cargo/env"
npm run tauri dev
```

FlowPilot stores local app data under the Tauri app data directory and uses SQLite for sessions, rules, browser events, and macOS window observations.

## macOS Permissions

FlowPilot can run without macOS permissions, but app/window detail quality is lower.

Required for accurate macOS collection:

- Accessibility: lets FlowPilot read focused app/window metadata such as window titles.
- Screen Recording: lets FlowPilot inspect the visible window list and titles. FlowPilot does not store screenshots or screen pixels.

Open System Settings > Privacy & Security, grant the permission to FlowPilot, then restart FlowPilot.

## Browser Domain Tracking

Chrome and Edge use the existing `browser-extension` package. The extension reports active tab domains to `http://127.0.0.1:17321/browser-event`.

Safari domain tracking requires a Safari Web Extension packaged through Xcode. The future Safari extension should send the same payload shape as the Chromium bridge:

```json
{
  "domain": "example.com",
  "title": "Example",
  "url": null
}
```

Until that package exists, Safari sessions are classified by app name and window title.

## Unsigned Local Packaging

Build an app bundle or DMG:

```bash
npm run tauri build -- --bundles app,dmg
```

Expected outputs are under `src-tauri/target/release/bundle/`.

## Developer ID Signing and Notarization

Direct distribution outside the Mac App Store requires Developer ID signing and notarization.

Release prerequisites:

- Apple Developer Program membership.
- Developer ID Application certificate installed in the macOS keychain.
- Apple Team ID.
- App Store Connect API key or Apple ID notarization credentials.

Configure Tauri's macOS signing and notarization environment variables according to the official Tauri macOS signing guide, then rebuild the DMG. Notarized releases should be stapled before distribution.

References:

- https://v2.tauri.app/distribute/sign/macos/
- https://v2.tauri.app/distribute/
- https://developer.apple.com/documentation/safariservices/safari-web-extensions
```

- [ ] **Step 2: Commit**

Run:

```bash
git add docs/macos-development.md
git commit -m "docs: add macos development guide"
```

## Task 10: Run Full Verification and Development App

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run frontend tests**

Run:

```bash
npm test
```

Expected: all Vitest frontend tests pass.

- [ ] **Step 2: Run browser-extension tests**

Run:

```bash
npm test --prefix browser-extension
```

Expected: browser bridge extension tests pass.

- [ ] **Step 3: Run Rust tests**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml
```

Expected: Rust tests pass on macOS. Windows-only tests remain cfg-gated.

- [ ] **Step 4: Run frontend production build**

Run:

```bash
npm run build
```

Expected: TypeScript and Vite build complete successfully.

- [ ] **Step 5: Run Tauri development app**

Run:

```bash
npm run tauri dev
```

Expected:

- FlowPilot window opens on macOS.
- App name remains FlowPilot.
- The sidebar and existing pages render.
- Permission notice appears if Accessibility or Screen Recording is missing.
- The app continues running if permissions are missing.
- Tray/menu item appears through the current Tauri tray setup.
- SQLite database is created in the Tauri app data directory.

Stop the dev app after verification.

- [ ] **Step 6: Build unsigned macOS bundle**

Run:

```bash
npm run tauri build -- --bundles app,dmg
```

Expected: `.app` and `.dmg` artifacts are produced under `src-tauri/target/release/bundle/`.

- [ ] **Step 7: Inspect git status**

Run:

```bash
git status --short
```

Expected: only intentional source, docs, and lockfile changes are present. Build artifacts and `node_modules` are not tracked.

## Plan Self-Review

- Spec coverage: The plan covers macOS window/app collection, domain-based browser reuse, Safari extension design, permission UX, tray confirmation, persistence, tests, dev run, `.app`/`.dmg`, and signing/notarization docs.
- Completeness scan: The plan contains concrete file, code, command, and expected-output steps.
- Type consistency: `ActivitySnapshot`, `WindowObservation`, `ActivitySnapshotReader`, `PlatformPermissionStatus`, and `MacosPermissionNotice` names are used consistently across tasks.
