# Pause and Quick Look Bugfix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the FSEvents Pause hang and make Space reliably toggle Quick Look from the focused results table.

**Architecture:** Keep `FSEventsWatcher` MainActor-owned while moving the thread-safe FSEvents context object to file scope so Core Services can retain and release it on its own queue. Handle Space at the results table boundary, preserving normal space entry in the search field and the existing menu action.

**Tech Stack:** Swift 6, SwiftUI on macOS 14+, Core Services FSEvents, XCTest, Swift Package Manager.

## Global Constraints

- V1 remains read-only and searches metadata only.
- Do not alter user files or broaden indexing scope.
- Preserve existing package boundaries and deployment target.
- Do not commit `.build`, `DerivedData`, or temporary distribution output.

---

### Task 1: FSEvents Pause lifecycle

**Files:**
- Modify: `Sources/MyMacSearchCore/Watching/FSEventsWatcher.swift`
- Create: `Tests/MyMacSearchCoreTests/FSEventsWatcherLifecycleTests.swift`

**Interfaces:**
- Consumes: `FSEventsWatcher.start(paths:since:onEvents:)` and `FSEventsWatcher.stop()`.
- Produces: a file-scope, lock-protected FSEvents callback context whose lifetime is safe on the Core Services queue.

- [x] **Step 1: Write the failing lifecycle test**

Create a real temporary directory, start `FSEventsWatcher`, stop it, and drain the injected dispatch queue. The break caught is `stop()` blocking or asserting when FSEvents releases its context off the MainActor.

- [x] **Step 2: Verify the regression is represented**

Use the captured live-app stack trace as the pre-fix failure evidence; do not rerun the known kernel-wedging path in the main test process.

- [x] **Step 3: Implement the minimal isolation fix**

Move the callback box out of the `@MainActor FSEventsWatcher` type, keep its `NSLock` synchronization, and update all `Unmanaged` references to the file-scope type.

- [x] **Step 4: Run the focused lifecycle test**

Run `swift test --filter FSEventsWatcherLifecycleTests` and require a clean pass.

### Task 2: Results-table Space key

**Files:**
- Modify: `Sources/MyMacSearchApp/Views/SearchResultsTable.swift`
- Create: `Sources/MyMacSearchAppSupport/ResultKeyboardCommand.swift`
- Create: `Tests/MyMacSearchAppSupportTests/ResultKeyboardCommandTests.swift`

**Interfaces:**
- Consumes: the selected result and `AppModel.toggleQuickLook()`.
- Produces: a small keyboard-command resolver and a table-scoped Space handler that toggles Quick Look only when the table has keyboard focus.

- [x] **Step 1: Write the failing command test**

Assert that Space maps to Quick Look and unrelated keys remain unhandled using literal expectations.

- [x] **Step 2: Run the focused test and confirm failure**

Run `swift test --filter ResultKeyboardCommandTests` and require failure because the resolver does not yet exist.

- [x] **Step 3: Implement and wire the command**

Add the minimal resolver in app-support code and use SwiftUI `onKeyPress` on the table to call `toggleQuickLook()` and return `.handled`.

- [x] **Step 4: Run the focused test and native build**

Require the command test to pass and the app target to compile with warnings treated as errors.

### Task 3: Release regression verification

**Files:**
- Modify: `docs/qa/2026-08-14-release-verification.md`
- Modify: `scripts/install-personal.sh`
- Modify: `Tests/MyMacSearchAppSupportTests/ReleasePackagingTests.swift`
- Modify: `../downloads/MyMacSearch/MyMacSearch-personal-mac.zip`

**Interfaces:**
- Consumes: the fixed source tree and existing packaging scripts.
- Produces: a verified personal ZIP and installed `/Applications/MyMacSearch.app`.

- [x] **Step 1: Run all automated tests**

Run all MyMacSearch tests, the scale test, and warnings-as-errors debug and release builds.

- [x] **Step 2: Exercise both fixes in the real UI**

Confirm Pause reaches `Paused`, Resume catches up filesystem changes, and Space opens and closes Quick Look from a selected result.

- [x] **Step 3: Package and install**

Bound the running-app quit request, build the app bundle, create the personal ZIP, install it in `/Applications`, and compare the packaged and installed executable hashes.

- [x] **Step 4: Verify release integrity**

Run strict codesign checks, ZIP integrity checks, bundle metadata checks, `git diff --check`, and a final changed-file review.
