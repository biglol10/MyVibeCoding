# SwiftUI macOS Native FlowPilot Design

## Goal

Build a native macOS FlowPilot app in SwiftUI while keeping the existing Tauri/React/Rust app and Windows build intact.

## Scope

The SwiftUI version starts as a separate macOS app under `macos-native/`. It should eventually replace the macOS Tauri app, but it must not break the current Windows/Tauri code path. The first milestone is a buildable native shell with the same product identity, app navigation, Korean UI copy, and a small local data model that mirrors the existing report concepts.

The initial SwiftUI app does not remove the existing React UI, Rust collector, browser extension, packaging scripts, or installed Tauri app. Migration happens in stages so the current app remains usable while the native implementation grows.

## Architecture

The repository will contain two app surfaces:

- Existing cross-platform app: `src/`, `src-tauri/`, `browser-extension/`
- New native macOS app: `macos-native/`

The native app uses SwiftUI for the main window, `MenuBarExtra` for the macOS menu bar item, and small Swift services for report state. It starts with mocked/sample report data so the UI can compile and be reviewed before collector and database migration. Later milestones can connect it to the existing SQLite database or port the Rust collector logic into Swift.

## Data Model

The native app should mirror the concepts already used by the Tauri app:

- `ActivityCategory`: productive, unproductive, neutral, ignored, uncategorized, idle
- `UsageItem`: app/domain name, category, duration, share, rule source
- `TimelineSession`: app/domain name, title, category, start/end time, duration
- `DashboardSummary`: total time, productive time, unproductive time, idle time, session count

This keeps the migration path clear and avoids inventing a new product model.

## UI

The SwiftUI app uses a native macOS split layout:

- Sidebar: FlowPilot identity, navigation, recording status
- Today: summary metrics, top usage list, weekly trend placeholder
- Timeline: hour-grouped session cards
- Weekly Report: weekly summary and app/site table placeholder
- Review: uncategorized item list with quick classification buttons
- Rules: rule list placeholder

The visual direction should be closer to a native macOS utility than a web dashboard: tighter spacing, system materials where appropriate, native table/list controls, and Korean labels.

## macOS Integration

The native app includes:

- App name: FlowPilot
- Bundle ID: `app.flowpilot.native`
- Menu bar item with quick summary
- Normal main window lifecycle

Future collector milestones will add:

- Accessibility permission detection/request guidance
- Screen Recording permission guidance
- window/app observation
- browser domain bridge migration or extension reuse

## Packaging

The initial milestone uses Swift Package Manager to compile a macOS executable for development verification. Later packaging should add an `.app` bundle and personal install script matching the current personal macOS package flow.

Developer ID signing and notarization remain a later release milestone.

## Testing

The first milestone should include Swift unit tests for report formatting and aggregation helpers. UI rendering is verified by building and launching the native app where the environment supports it.

The existing Tauri app tests must continue to pass when native files are added.

## Non-Goals For First Milestone

- Do not delete the current React/Tauri app.
- Do not replace the Rust collector in one step.
- Do not migrate historical SQLite data yet.
- Do not remove or rewrite the browser extension.
- Do not change Windows build artifacts or Windows behavior.
