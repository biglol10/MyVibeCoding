# Calendar Search UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect local title/notes search to the main macOS calendar UI with deterministic results and direct event editing.

**Architecture:** `EventService` owns matching and ordering. `MainWindowView` owns query/focus/navigation state, while a dedicated search view file renders the compact field and fixed-width result panel. A notification-backed Find command focuses the active field.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, SwiftPM, macOS 14+

## Global Constraints

- Preserve the existing 1240 x 680 minimum layout and 280-point side panel.
- Do not filter or resize the month grid while searching.
- Do not add persistence, network, or third-party dependencies.
- Follow TDD and run the full suite before commit.

---

### Task 1: Deterministic Search Results

**Files:**
- Modify: `Tests/MyMacCalendarCoreTests/EventServiceTests.swift`
- Modify: `Sources/MyMacCalendarCore/Services/EventService.swift`

**Interfaces:**
- Consumes: `EventService.search(_:in:)`
- Produces: case-insensitive title/notes matches sorted by start date then title

- [x] **Step 1: Write a failing behavior test**

Add a test with whitespace around the query and deliberately unsorted events. Assert that matching results are ordered by start date, then localized title.

- [x] **Step 2: Run the focused test and verify RED**

Run: `swift test --disable-sandbox --filter EventServiceTests/testSearchTrimsQueryAndSortsByDateThenTitle`

Expected: failure because current search preserves input order.

- [x] **Step 3: Implement deterministic ordering**

Trim/lowercase the query as today, filter title and notes, then sort matches by `startDate` and localized case-insensitive title.

- [x] **Step 4: Run EventService tests and verify GREEN**

Run: `swift test --disable-sandbox --filter EventServiceTests`

Expected: all EventService tests pass.

### Task 2: Search Field, Result Panel, and Find Command

**Files:**
- Create: `Tests/MyMacCalendarCoreTests/CalendarSearchSourceTests.swift`
- Create: `Sources/MyMacCalendar/Views/CalendarSearchView.swift`
- Modify: `Sources/MyMacCalendar/Views/MainWindowView.swift`
- Modify: `Sources/MyMacCalendar/App/AppCommandNotifications.swift`
- Modify: `Sources/MyMacCalendar/App/MyMacCalendarApp.swift`

**Interfaces:**
- Consumes: `EventService.search(_:in:)`, `CalendarEvent`, `ActiveSheet.editEvent`
- Produces: `CalendarSearchField`, `CalendarSearchResultsView`, `.focusCalendarSearch`

- [x] **Step 1: Write a failing source-wiring test**

Assert that the main window owns search state, switches the side panel, selects the event date before editing, and that the app adds a `Command-F` search command after the supported `.pasteboard` command placement. The current SwiftUI SDK does not expose `CommandGroupPlacement.find`.

- [x] **Step 2: Run the focused test and verify RED**

Run: `swift test --disable-sandbox --filter CalendarSearchSourceTests`

Expected: failure because the search views and wiring do not exist.

- [x] **Step 3: Implement the minimal search UI**

Add the fixed-width field, result/empty states, clear action, result callback, search focus notification, and Find command. Keep all rows clipped and one-line where needed.

- [x] **Step 4: Run focused tests and verify GREEN**

Run: `swift test --disable-sandbox --filter CalendarSearchSourceTests`

Expected: all search source tests pass.

### Task 3: Documentation and End-to-End Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/verification/2026-08-04-full-feature-audit.md`

**Interfaces:**
- Consumes: completed search workflow
- Produces: current feature documentation and verified checklist status

- [x] **Step 1: Update current documentation**

Move search from known limitations to main features and record the new UI smoke evidence without changing unrelated audit history.

- [x] **Step 2: Run full verification**

Run:

```bash
swift test --disable-sandbox --no-parallel
swift build -c release --disable-sandbox
./scripts/build_app.sh
git diff --check
```

Expected: 0 test failures, successful release/app builds, and no whitespace errors.

- [x] **Step 3: Run isolated app smoke**

Use a unique bundle identifier and temporary `MYMACCALENDAR_STORE_URL`. Create title/notes fixtures and verify the field, result panel, no-result state, clear, date jump/editor, `Command-F`, and Escape. Remove only the isolated store and preferences afterward.

- [x] **Step 4: Commit the completed task**

Stage the search implementation, tests, and current docs. Commit with a focused message after reviewing the staged diff.
