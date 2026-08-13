# Native macOS Stability and Collection Controls Design

**Date:** 2026-08-13

**Status:** Approved for implementation planning

## Goal

Harden the recommended SwiftUI native macOS path against incorrect time aggregation, malformed browser-bridge requests, transient SQLite contention, and hidden data-source failures, while adding a small, reversible collection pause/resume control. The Tauri/React and Windows paths remain behaviorally unchanged and serve as regression checks.

## Current Evidence

- Root frontend tests pass: 69 Vitest tests and 10 packaging-script tests.
- Browser extension tests pass: 6 Vitest tests.
- Rust tests pass: 65 tests.
- Native Swift tests pass: 43 tests.
- Playwright passes 5 tests with 1 desktop-only narrow-layout test intentionally skipped.
- Frontend and native release builds pass. The frontend build reports a non-blocking large-chunk warning for the approximately 684 KB minified application bundle.
- The current native build launches successfully and the Today, Timeline, Weekly Report, Uncategorized Review, and Rules screens render with the real local database.

These checks establish a healthy baseline, but they do not cover long sampling gaps, hostile or malformed local HTTP input, SQLite lock contention, or user-visible native recovery paths.

## Scope

### Included

1. Split native activity sessions after an unexpectedly long interval so sleep, excluded FlowPilot foreground time, a legacy Tauri pause, or a manual pause cannot inflate a session duration.
2. Harden the native loopback browser bridge against oversized input, duplicate headers, incomplete bodies, and database write failures.
3. Make the browser bridge restartable after listener failure and expose a user-triggered retry.
4. Add a short SQLite busy timeout and atomic transactions for multi-row native writes.
5. Surface report-database load failures instead of silently presenting fallback data as an ordinary sample-data state.
6. Add an in-memory collection pause/resume control to the native sidebar and menu bar.
7. Preserve existing behavior in the Tauri/React app, Windows collector, and Chromium extension unless a regression test requires a compatibility correction.

### Excluded

- A full actor or background-worker rewrite of the native collector.
- Login-item management or launch-at-login.
- A new Settings screen.
- Persistent pause state across application launches.
- New analytics, goals, notifications, cloud sync, or account features.
- Public distribution signing, notarization, or Intel/universal packaging changes.
- Frontend bundle code splitting, because the current warning is a performance optimization rather than a demonstrated native stability defect.

## Architecture

The change keeps the existing three-part native structure:

- `FlowPilotNativeCore` owns deterministic, platform-independent session, HTTP parsing, database, and report-state behavior that can be unit tested.
- `FlowPilotNative` owns AppKit/SwiftUI lifecycle, `NWListener`, timer coordination, and user controls.
- The existing browser extension remains the producer of authenticated loopback `POST /browser-event` requests.

Pure request validation will move out of `NativeBrowserBridgeService` into a core parser. The network service will remain responsible for receiving bytes, applying the request-size ceiling before accumulation grows, saving an accepted event, and selecting the final HTTP response. This boundary makes malformed-request behavior testable without opening a real port.

The collector remains `@MainActor` for this iteration. The work performed every five seconds is bounded, and moving AppKit, AppleScript, database, and observable state across actor boundaries would materially expand the change. The design instead removes correctness failures and adds explicit recovery paths without changing the concurrency model.

## Session Continuity

`ActivitySessionAccumulator` will receive a maximum merge gap. The production default will be greater than the normal five-second sample interval while still short enough to exclude sleep and pause gaps. A value of 15 seconds is the initial contract.

Two samples may merge only when:

- app, process, domain, idle state, and normalized title rules still match; and
- the next observation occurs from 0 through 15 seconds after the previous observation.

A negative time delta or a delta greater than 15 seconds starts a new session. When a manual pause begins, the collector explicitly resets its open accumulator state. This prevents a resume on the same app and title from bridging the paused period.

Legacy Tauri detection continues to pause native sampling. Because the gap rule is authoritative, returning from a Tauri pause or from foreground use of FlowPilot cannot merge across the unobserved interval even if the previous app becomes active again.

## Browser Bridge Hardening

The parser will accept only:

- `POST /browser-event`;
- `Content-Type: application/json`, ignoring optional parameters and case;
- the exact `x-flowpilot-bridge: flowpilot-browser-bridge-v1` marker;
- a complete body no larger than 16 KiB; and
- a decodable `BrowserEventDraft`.

Duplicate header names will be rejected with HTTP 400 rather than passed to a dictionary initializer that can trap. The receiver will allow at most 4 KiB of request line and headers plus the existing 16 KiB body limit, for a 20 KiB total request ceiling. It will enforce that ceiling before recursively receiving more bytes, so a client that never terminates its headers cannot grow memory without limit.

The network response will reflect persistence:

- `204` only after the database save succeeds;
- `400`, `403`, `404`, `405`, or `413` for the existing client errors; and
- `500` when persistence fails.

On listener failure, the service will release the failed listener so `start()` can be called again. The Today screen will provide a compact retry button when the bridge is not running and has an error. Automatic aggressive retry is excluded because port occupation by the legacy Tauri app is an expected state and should not create a retry loop.

## SQLite Reliability

Every native SQLite connection will set a 2,000 ms busy timeout immediately after opening. This allows brief writes from another FlowPilot process or connection to finish instead of immediately dropping a sample or rule edit.

`saveSessions` and `saveWindowObservations` will wrap their multi-statement work in a transaction. The transaction commits only after all statements succeed and rolls back on failure. Single-statement operations retain their current structure.

Schema compatibility and the existing database location remain unchanged. No migration that deletes or rewrites existing activity data is introduced.

## Report Error Visibility

If the database does not exist, the current explicit sample-data fallback remains available. If the database exists but cannot be opened or queried, the store will:

- retain the most recent successfully loaded report data when available;
- otherwise use the existing fallback data;
- set the source label to indicate that the displayed data is fallback or stale because of a database error; and
- expose the localized database error on the Today screen with a retry action.

A failed refresh must not clear `lastError` indirectly through fallback application. A successful refresh clears the error and restores the normal source label.

## Collection Controls

The native collector gains a distinct manual-pause state separate from timer lifecycle and legacy-Tauri pause state.

- `pause()` stops collection, resets the open session accumulator, and shows `사용자 일시정지`.
- `resume()` restarts the timer and immediately performs a fresh observation.
- Calling either operation repeatedly is safe.
- Pause state is not persisted. Launching FlowPilot always starts collection unless the legacy Tauri app is running.

The sidebar status will distinguish active collection, manual pause, legacy-app pause, and collection error. The menu bar will offer either `수집 일시정지` or `수집 재개`, depending on state. Existing quit and refresh actions remain.

## Data Flow

1. The five-second timer asks `MacActivityReader` for a snapshot.
2. The collector checks legacy and manual pause states before reading.
3. The accumulator either extends the current session or splits it using identity and maximum-gap rules.
4. Recent browser events may enrich a Chromium session with a domain.
5. Session and throttled window-observation writes use the native SQLite reliability policy.
6. A successful save refreshes the report store; failures remain visible without claiming success.
7. Browser-extension requests travel through the bounded parser, persistence step, and truthful HTTP response path.

## Error Handling

- Reader failure or the absence of an eligible foreground app produces no sample and does not crash the timer.
- Session gaps prevent missing observations from being counted as active time.
- SQLite lock contention waits up to two seconds; a remaining failure is shown to the user and retried on the next normal collection tick or explicit refresh.
- Browser persistence failures return HTTP 500 and remain visible in the native UI.
- Listener failure releases its listener and enables manual retry.
- Manual pause and resume are idempotent and cannot create duplicate timers.

## Testing

Implementation follows red-green-refactor for every behavior change.

Native core unit tests will cover:

- merging within the 15-second gap;
- splitting after a long or negative gap;
- reset behavior before a same-window resume;
- valid browser requests;
- duplicate and malformed headers, including the 4 KiB header ceiling;
- incomplete and oversized requests;
- correct client-error classification;
- transactional rollback where a multi-row write fails;
- brief SQLite contention that resolves within the busy timeout;
- missing-database fallback versus existing-database read failure; and
- clearing a report error after a later successful refresh.

A small `CollectionControlState` value in `FlowPilotNativeCore` will define the idempotent manual pause/resume transitions, and the native collector will apply those transitions to its timer and accumulator. A core response-mapping helper will select HTTP 204 only for successful persistence and HTTP 500 for failed persistence. These extracted policies will be unit tested directly; listener release/retry wiring and SwiftUI presentation will be verified in the rebuilt application because they depend on `NWListener` and AppKit lifecycle behavior.

Final verification will run:

```text
npm test
npm run build
npm test --prefix browser-extension
npm run build --prefix browser-extension
npm run e2e
cargo test --manifest-path src-tauri/Cargo.toml
swift test --package-path macos-native
swift build -c release --package-path macos-native
```

The current native app will then be rebuilt and opened to verify Today, sidebar status, bridge retry, menu-bar pause/resume, and navigation across all five screens. Passing automated tests will not be reported as proof of macOS privacy permission grants, long-running energy behavior, public signing, or notarization.

## Success Criteria

- A gap longer than 15 seconds never inflates one native activity session.
- Manual pause excludes the paused interval and resume creates a fresh session boundary.
- Malformed or oversized loopback requests cannot crash the parser or grow request memory without the configured bound.
- The browser bridge never returns 204 for a database write failure and can be retried after listener failure.
- Short SQLite contention is tolerated and multi-row writes are atomic.
- Existing database failures are clearly visible and cannot masquerade as ordinary sample data.
- All baseline automated checks continue to pass.
- The rebuilt native app exposes correct collection state and pause/resume behavior in the actual macOS UI.
