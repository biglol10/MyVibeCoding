# Calendar UI Redesign Implementation Plan

Status: Historical implementation plan. This file is kept for traceability; some planned steps and snippets may differ from the current implementation. Use `README.md`, current source files, and tests as the source of truth.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the weak card-like month UI with a professional dark full-grid calendar inspired by the approved reference.

**Architecture:** Keep the existing SwiftData models and app scenes. Replace `NavigationSplitView` with a single full-window calendar surface, and make `MonthGridView` responsible for fixed 7x6 month layout, date styling, event pills, holiday pills, and cell interactions.

**Tech Stack:** SwiftUI, SwiftData, MyMacCalendarCore services and models, AppKit only through existing app/window hooks.

---

### Task 1: Replace Main Window Shell

**Files:**
- Modify: `Sources/MyMacCalendar/Views/MainWindowView.swift`

- [ ] **Step 1: Remove permanent split panel**

Replace `NavigationSplitView` with a single `VStack` full-window layout. Keep `@Query` rows, `displayedMonth`, `selectedDate`, `activeSheet`, and widget refresh behavior.

- [ ] **Step 2: Add reference-style top bar**

Create a large Korean title from `displayedMonth`, right-aligned previous/today/next buttons, quick add, new event, and settings buttons. Use compact icon buttons where possible.

- [ ] **Step 3: Wire actions**

Previous/next update `displayedMonth`, Today updates both displayed and selected date, plus opens `EventEditorView(defaultDate: selectedDate)`, quick add opens `QuickAddView`, settings sends `showSettingsWindow:`.

- [ ] **Step 4: Build check**

Run `swift build` or the available build script. Expected: build passes, or existing sandbox/cache blocker is reported with the exact error.

### Task 2: Rebuild Month Grid

**Files:**
- Modify: `Sources/MyMacCalendar/Views/MonthGridView.swift`

- [ ] **Step 1: Add event selection callbacks**

Change the view API to accept `onCreateEvent: (Date) -> Void` and `onSelectEvent: (CalendarEvent) -> Void`.

- [ ] **Step 2: Replace card grid with fixed calendar grid**

Use weekday header plus 42 cells in a 7x6 grid. Draw thin dividers and a single dark background instead of rounded date-card backgrounds.

- [ ] **Step 3: Add professional date styling**

Top-right date numbers, muted adjacent-month days, red today badge, subtle selected-day background, red Sunday/holiday text, blue Saturday text.

- [ ] **Step 4: Render pills**

Render visible non-hidden holidays first, then events. Use purple holiday pills with a star icon and event-color pills for user events. Limit to three rows and show `+N` overflow.

- [ ] **Step 5: Add interactions**

Single-click selects a date. Double-click creates a new event for that date. Clicking a pill opens its editor.

- [ ] **Step 6: Build check**

Run `swift build`. Expected: compile errors, if any, are limited to changed view signatures and fixed immediately.

### Task 3: Polish Supporting Views

**Files:**
- Modify: `Sources/MyMacCalendar/Views/EventEditorView.swift`
- Modify: `Sources/MyMacCalendar/Views/QuickAddView.swift`
- Modify: `Sources/MyMacCalendar/Views/SettingsView.swift`
- Modify: `Sources/MyMacCalendar/Views/FloatingWidgetView.swift`

- [ ] **Step 1: Event editor polish**

Improve grouping, spacing, labels, and destructive delete placement without changing save/delete behavior.

- [ ] **Step 2: Quick add polish**

Make preview state look intentional and remove unfinished GroupBox styling.

- [ ] **Step 3: Settings polish**

Keep tabs but improve holiday row layout, button labels, and form density.

- [ ] **Step 4: Widget polish**

Apply the same restrained dark style and keep today's event visually distinct.

- [ ] **Step 5: Behavior check**

Confirm save, delete, manual holiday add, imported holiday hide/delete, quick add, and widget rendering paths still use the existing model/service behavior.

### Task 4: Verification

**Files:**
- Test: `Tests/MyMacCalendarCoreTests/*`
- Build scripts: `scripts/build_app.sh`, `scripts/package_personal.sh`

- [ ] **Step 1: Run tests**

Run `swift test`. Expected: all existing core tests pass, or sandbox/cache blocker is recorded.

- [ ] **Step 2: Build app bundle**

Run `./scripts/build_app.sh`. Expected: `build/MyMacCalendar.app` exists, or the existing SwiftPM sandbox issue is recorded.

- [ ] **Step 3: Inspect main UI**

Launch the app when possible and verify the main screen no longer contains `NavigationSplitView` right panel or vertical rounded day-card design.

- [ ] **Step 4: Final report**

Report changed files, what was verified, and any build/runtime blocker.
