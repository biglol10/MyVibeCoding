# MyMacCalendar Stability Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:test-driven-development` for each task and `superpowers:verification-before-completion` before reporting status.

**Goal:** Make persistence, recurrence notifications, asynchronous notification updates, and settings repair fail safely without touching the user's real store during verification.

**Architecture:** Keep SwiftData models behind a fail-closed bootstrap and a shared rollback transaction. Convert model objects to immutable snapshots before asynchronous work. Generate recurrence and notification plans as pure values, then reconcile them through an injectable main-actor notification client with per-event generations.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, UserNotifications, XCTest, macOS 14+

## Global Constraints

- Preserve all existing uncommitted changes.
- Do not delete, replace, or migrate a real user store.
- Do not commit, push, or open a PR.
- Use only in-memory stores, temporary directories, or disposable store copies in tests.
- Treat CAL-002 as unresolved unless a store created by the actual previous schema is migrated and reopened successfully.

---

### Task 1: Fail-Closed Store Bootstrap and Rollback Transactions

**Files:**
- Modify: `Sources/MyMacCalendarCore/Stores/CalendarStore.swift`
- Create: `Sources/MyMacCalendarCore/Stores/PersistenceTransaction.swift`
- Modify: `Sources/MyMacCalendar/App/MyMacCalendarApp.swift`
- Create: `Sources/MyMacCalendar/Views/StorageFailureView.swift`
- Modify: `Sources/MyMacCalendar/Views/QuickAddView.swift`
- Modify: `Sources/MyMacCalendar/Views/EventEditorView.swift`
- Modify: `Sources/MyMacCalendar/Views/SettingsView.swift`
- Modify: `Sources/MyMacCalendarCore/Stores/SettingsStore.swift`
- Test: `Tests/MyMacCalendarCoreTests/PersistenceTransactionTests.swift`
- Test: `Tests/MyMacCalendarCoreTests/CalendarStoreFailureTests.swift`
- Test: `Tests/MyMacCalendarCoreTests/AppResilienceSourceTests.swift`

**Interfaces:**
- `CalendarStore.makeContainer() throws -> ModelContainer` creates only the persistent production container.
- Internal `CalendarStore.makeInMemoryContainer() throws -> ModelContainer` remains test-only.
- `PersistenceTransaction.save(context:)` calls `rollback()` before rethrowing any save error.
- `CalendarApplicationState` is either `.ready(ModelContainer)` or `.failed` with a path-free user-facing failure.

- [x] Add deterministic failing tests for a non-directory store parent, rollback on save failure, and app source without memory fallback.
- [x] Run the focused tests and confirm expected failures.
- [x] Implement the production-only persistent bootstrap and shared transaction.
- [x] Route every user save path through the shared transaction and keep sheets open on failure.
- [x] Verify focused tests; full verification is tracked in Task 5.

### Task 2: Settings Validation at Read, Write, and Render Boundaries

**Files:**
- Create: `Sources/MyMacCalendarCore/Services/SettingsValidation.swift`
- Modify: `Sources/MyMacCalendarCore/Stores/SettingsStore.swift`
- Modify: `Sources/MyMacCalendar/Views/SettingsView.swift`
- Modify: `Sources/MyMacCalendar/Views/MainWindowView.swift`
- Modify: `Sources/MyMacCalendar/Controllers/WidgetCoordinator.swift`
- Modify: `Sources/MyMacCalendarCore/Services/EventService.swift`
- Test: `Tests/MyMacCalendarCoreTests/SettingsValidationTests.swift`

**Interfaces:**
- `SettingsValidation.snapshot(_:)` always returns finite opacity, bounded counts/time, and known theme/density strings.
- `SettingsValidation.repair(_:)` mutates persisted fields to the same normalized values and reports whether a save is needed.
- `SettingsValidation.opacityPercent(_:)` never converts a non-finite value to `Int`.

- [x] Add failing boundary tests for visible count, opacity, percent, time, theme, density, and rollback re-exposure.
- [x] Run the focused tests and confirm expected failures.
- [x] Implement validation and use it at all render and persistence boundaries.
- [x] Verify focused tests; full verification is tracked in Task 5.

### Task 3: Recurrence and Global Notification Planning

**Files:**
- Create: `Sources/MyMacCalendarCore/Services/EventRecurrence.swift`
- Create: `Sources/MyMacCalendarCore/Services/NotificationPlanning.swift`
- Modify: `Sources/MyMacCalendarCore/Services/RecurrenceExpander.swift`
- Replace: `Sources/MyMacCalendarCore/Services/NotificationService.swift`
- Test: `Tests/MyMacCalendarCoreTests/RecurrenceExpanderTests.swift`
- Test: `Tests/MyMacCalendarCoreTests/NotificationPlanningTests.swift`

**Interfaces:**
- `CalendarEventSnapshot` is a SwiftData-free immutable value.
- `EventRecurrenceCalculator` fast-forwards weekly, monthly, and yearly schedules near a requested interval.
- `NotificationPlanner.plans(for:defaultHour:defaultMinute:now:horizonDays:maximumPlans:batchID:)` returns globally sorted plans capped after sorting by fire date.

- [x] Add failing tests for weekly, month-end, leap day, old anchors, fire-date horizon, invalid offsets, identifiers, and a global cap.
- [x] Run the focused tests and confirm expected failures.
- [x] Implement fast-forward recurrence and pure notification planning.
- [x] Verify focused tests; full verification is tracked in Task 5.

### Task 4: Race-Safe Notification Reconciliation

**Files:**
- Create: `Sources/MyMacCalendarCore/Services/NotificationClient.swift`
- Create: `Sources/MyMacCalendarCore/Services/NotificationReconciler.swift`
- Create: `Sources/MyMacCalendarCore/Services/NotificationUpdateCoordinator.swift`
- Modify: `Sources/MyMacCalendar/Views/EventEditorView.swift`
- Modify: `Sources/MyMacCalendar/Views/MainWindowView.swift`
- Create: `Sources/MyMacCalendar/Controllers/AppNotificationCoordinator.swift`
- Test: `Tests/MyMacCalendarCoreTests/NotificationReconcilerTests.swift`
- Test: `Tests/MyMacCalendarCoreTests/NotificationUpdateCoordinatorTests.swift`

**Interfaces:**
- `@MainActor NotificationClient` abstracts authorization, pending identifiers, add, and remove.
- `NotificationReconciler` performs authorization first, stages a full batch, removes stale identifiers only after all additions succeed, and removes the staged batch on failure or invalid generation.
- `NotificationUpdateCoordinator` owns per-event monotonic generations, deletion precedence, refresh generations, live event IDs, and orphan cleanup.

- [x] Add a controllable fake client and all required race/failure tests.
- [x] Run the focused tests and confirm expected failures.
- [x] Implement reconciler/coordinator and integrate immutable snapshots into the app.
- [x] Verify focused tests; full verification is tracked in Task 5.

### Task 5: Legacy Compatibility and End-to-End Verification

**Files:**
- Modify only if proven safe: SwiftData schema/migration files and relevant migration tests.
- Update: `README.md` only for verified behavior and explicitly deferred risk.

- [x] Create a disposable legacy store from the actual pre-change commit when feasible.
- [x] Attempt migration only on a copy; compare fields/offsets, reopen, and repeat.
- [x] Run package dump, parse, typecheck, tests, release build, plist/entitlement lint, script syntax checks, and `git diff --check`.
- [x] Launch the app only with an isolated store URL and smoke the successful and startup-failure paths.
- [x] Report any unverified legacy or real UserNotifications behavior as partial completion.
