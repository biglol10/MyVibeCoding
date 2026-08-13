# Calendar Stability Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve valid reminders when stored data is partly corrupt, make Quick Add safe for ambiguous and leap-day input, and keep the fixed-size floating widget fully reachable after display changes.

**Architecture:** Keep date and notification decisions in `MyMacCalendarCore` as deterministic value logic with XCTest coverage. SwiftUI/AppKit code consumes those decisions and owns only presentation or window lifecycle behavior. Existing uncommitted correctness fixes remain intact.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Foundation, SwiftData, XCTest

## Global Constraints

- Support macOS 14 and later.
- Do not access the user's real Application Support store during testing.
- Do not change the SwiftData schema.
- Do not add external dependencies.
- Do not commit or push unless the user separately requests it.

---

### Task 1: Preserve Valid Notification Offsets

**Files:**
- Modify: `Tests/MyMacCalendarCoreTests/NotificationPlanningTests.swift`
- Modify: `Sources/MyMacCalendarCore/Services/NotificationPlanning.swift`

**Interfaces:**
- Consumes: `NotificationPlanner.plans(for:defaultHour:defaultMinute:now:horizonDays:maximumPlans:batchID:)`
- Produces: Per-offset viability filtering that drops only offsets whose expansion cannot be represented.

- [x] Add a regression test with offsets `[Int.max, 1]` and assert that the one-day reminder is still planned.
- [x] Run the focused test and verify it fails because the current event-level overflow guard returns no plans.
- [x] Filter unrepresentable offsets before selecting the maximum expansion offset.
- [x] Run `NotificationPlanningTests` and verify all planning behavior passes.

### Task 2: Make Quick Add Date Handling Explicit

**Files:**
- Modify: `Tests/MyMacCalendarCoreTests/QuickAddParserTests.swift`
- Create: `Tests/MyMacCalendarCoreTests/QuickAddSubmissionPolicyTests.swift`
- Modify: `Sources/MyMacCalendarCore/Services/QuickAddParser.swift`
- Create: `Sources/MyMacCalendarCore/Services/QuickAddSubmissionPolicy.swift`
- Modify: `Sources/MyMacCalendar/Views/QuickAddView.swift`

**Interfaces:**
- Consumes: `QuickAddResult.needsConfirmation`
- Produces: `QuickAddSubmissionPolicy.decision(for:) -> QuickAddSubmissionDecision`

- [x] Add leap-day tests for a non-leap current year and a leap day that already passed.
- [x] Run the parser tests and verify they fail because slash parsing only checks the current and following year.
- [x] Search forward for the next valid month/day without rolling invalid dates.
- [x] Add policy tests proving confirmed input saves immediately and ambiguous input requires explicit confirmation.
- [x] Run the policy tests and verify they fail because the policy type does not exist.
- [x] Implement the small policy type and connect `QuickAddView` to a confirmation dialog before saving fallback-today input.
- [x] Run parser and policy tests and verify they pass.

### Task 3: Keep the Floating Widget Reachable

**Files:**
- Create: `Tests/MyMacCalendarCoreTests/WidgetFramePlacementTests.swift`
- Create: `Sources/MyMacCalendarCore/Services/WidgetFramePlacement.swift`
- Modify: `Sources/MyMacCalendar/Controllers/FloatingWidgetController.swift`

**Interfaces:**
- Produces: `WidgetFramePlacement.clampedFrame(_:visibleFrames:fallback:) -> CGRect`

- [x] Add tests for a mostly off-screen frame, removed display, and non-finite stored origin.
- [x] Run the focused tests and verify they fail because the placement type does not exist.
- [x] Implement deterministic frame validation and full-frame clamping.
- [x] Use it when restoring a stored widget origin.
- [x] Observe display-parameter changes and revalidate an existing widget window immediately.
- [x] Run the placement tests and widget source tests.

### Task 4: Verify and Document

**Files:**
- Modify: `README.md`
- Create: `docs/verification/2026-08-13-stability-followup.md`

**Interfaces:**
- Produces: A current record of the fixes, commands, isolated smoke path, and remaining environment-dependent risks.

- [x] Run all Swift tests without parallelism.
- [x] Parse all Swift sources and tests, then run a release build and app bundle build.
- [x] Lint plist/entitlements and shell scripts, verify code signing, and run `git diff --check`.
- [x] Launch an isolated app copy and exercise Quick Add confirmation and widget display behavior without the user store.
- [x] Update user documentation without rewriting historical audit results.
- [x] Review the final diff for unrelated changes and report the uncommitted working-tree state.
