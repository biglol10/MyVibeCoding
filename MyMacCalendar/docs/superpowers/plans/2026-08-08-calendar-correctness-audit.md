# Calendar Correctness Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix reproducible calendar, floating-widget, notification, and holiday-refresh defects without changing the SwiftData schema or touching real user data.

**Architecture:** Keep boundary validation and scheduling decisions in `MyMacCalendarCore`, then keep AppKit/SwiftUI files responsible only for rendering and orchestration. Every behavior change starts with a focused failing XCTest, and automatic holiday refresh reuses the same import planning path as the manual Settings action.

**Tech Stack:** Swift 6, SwiftUI, AppKit, SwiftData, XCTest, Foundation URLSession

## Global Constraints

- Preserve the current SwiftData schema and existing persistent stores.
- Do not use the real Application Support store in tests or smoke checks.
- Do not commit, push, or create a PR unless the user requests it separately.
- Do not weaken hidden-holiday persistence or notification generation safeguards.

---

### Task 1: Defensive Scheduling Boundaries

**Files:**
- Modify: `Tests/MyMacCalendarCoreTests/NotificationPlanningTests.swift`
- Modify: `Tests/MyMacCalendarCoreTests/EventServiceTests.swift`
- Modify: `Sources/MyMacCalendarCore/Services/NotificationPlanning.swift`
- Modify: `Sources/MyMacCalendarCore/Services/EventService.swift`

**Interfaces:**
- Consumes: existing `NotificationPlanner.plans` and `EventService.upcomingOccurrences`
- Produces: overflow-safe notification expansion and an empty result for negative horizons

- [x] Add tests for `Int.max` notification offsets and negative occurrence horizons.
- [x] Run the focused tests and confirm the current implementation fails for the intended reason.
- [x] Guard integer addition with `addingReportingOverflow` and reject negative horizons at the service boundary.
- [x] Re-run both focused suites and confirm they pass.

### Task 2: Occurrence-Accurate Widget Details

**Files:**
- Create: `Sources/MyMacCalendarCore/Models/EventOccurrenceDetail.swift`
- Create: `Tests/MyMacCalendarCoreTests/EventOccurrenceDetailTests.swift`
- Modify: `Sources/MyMacCalendar/Views/FloatingWidgetView.swift`
- Modify: `Sources/MyMacCalendar/Controllers/FloatingWidgetController.swift`
- Modify: `Sources/MyMacCalendar/Controllers/WidgetCoordinator.swift`
- Modify: `Tests/MyMacCalendarCoreTests/FloatingWidgetSourceTests.swift`

**Interfaces:**
- Consumes: `CalendarEvent` metadata and the selected `EventOccurrence`
- Produces: immutable `EventOccurrenceDetail` values whose dates match the clicked occurrence

- [x] Add a failing behavior test proving a recurring occurrence uses its occurrence dates and preserves the event metadata.
- [x] Add the immutable detail value and switch the detail window away from live SwiftData models.
- [x] Update source-wiring assertions and run the focused tests.

### Task 3: Predictable Widget Visibility

**Files:**
- Create: `Sources/MyMacCalendarCore/Services/WidgetVisibilityState.swift`
- Create: `Tests/MyMacCalendarCoreTests/WidgetVisibilityStateTests.swift`
- Modify: `Sources/MyMacCalendar/Controllers/WidgetCoordinator.swift`

**Interfaces:**
- Produces: `WidgetVisibilityState.updateConfiguredEnabled(_:)`, `toggleManually()`, and `isVisible`

- [x] Add failing tests for menu overrides and later Settings changes.
- [x] Implement the state machine so an actual persisted setting change clears a stale menu override.
- [x] Wire `WidgetCoordinator` to the state machine and run focused tests.

### Task 4: Durable Holiday Import and Annual Refresh

**Files:**
- Modify: `Sources/MyMacCalendarCore/Services/HolidayService.swift`
- Modify: `Tests/MyMacCalendarCoreTests/HolidayServiceTests.swift`
- Modify: `Sources/MyMacCalendar/Views/SettingsView.swift`
- Modify: `Sources/MyMacCalendar/Views/MainWindowView.swift`
- Modify: `Tests/MyMacCalendarCoreTests/SettingsBehaviorSourceTests.swift`
- Modify: `README.md`
- Modify: `docs/verification/2026-08-04-full-feature-audit.md`

**Interfaces:**
- Produces: `HolidayImportPlanner.newRecords(imports:existing:year:)` and `HolidayAutoRefreshPolicy.shouldFetch(...)`
- Consumes: current-year API records, session-attempted years, `HolidayService.fetchKoreanHolidays`, and `PersistenceTransaction.save`

- [x] Add tests proving a hidden API date stays hidden even if the provider title changes, imports do not duplicate, and only an unfetched current year is eligible once per session.
- [x] Run focused tests to observe the missing behavior.
- [x] Centralize import planning and use it from manual and automatic refresh paths.
- [x] Trigger current-year refresh on app start, calendar-day change, and the existing 12-hour maintenance tick; keep failures non-destructive and private.
- [x] Update source-wiring tests and documentation, then run focused tests.

### Task 5: Full Verification and Isolated Smoke Test

**Files:**
- Modify only if verification exposes a regression.

**Interfaces:**
- Consumes: all changes from Tasks 1-4
- Produces: command evidence and isolated UI/runtime evidence

- [x] Run parse, Swift 6 typecheck where applicable, the complete test suite, release build, plist/script lint, and `git diff --check`.
- [x] Build and launch the app with an isolated temporary SwiftData store.
- [x] Exercise event creation/edit/delete, recurring occurrence detail, widget visibility, Settings, and holiday refresh without touching the real store.
- [x] Inspect logs for crashes or private event content and report any environment-limited checks explicitly.
