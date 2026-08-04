# Rename, Search, and Filesystem Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore reliable inline rename and remove the identified data-loss and stale-async hazards in recursive search, pane loading, Trash rollback, canonical path validation, case-only rename, and compound Undo.

**Architecture:** Keep the existing SwiftUI/AppKit hybrid and `ExplorerStore` ownership model. Add narrow identity/context snapshots and generation tokens at asynchronous commit boundaries, centralize canonical filesystem identity checks inside file-operation helpers, and make compound Undo transactional through explicit preflight and rollback journals.

**Tech Stack:** Swift 6.1, SwiftUI, AppKit, Foundation, XCTest, Swift Package Manager, ZIPFoundation, macOS 15+

## Global Constraints

- Use the current clone as source of truth; do not apply old line numbers or patches blindly.
- Preserve user changes and do not reset, restore, clean, or push.
- Add a failing regression test before each production change.
- Use only UUID-named paths under `FileManager.default.temporaryDirectory` for mutation tests.
- Inject simulated Trash behavior; do not touch the user's real Trash or existing home-directory files.
- Do not update dependencies or rewrite the architecture.
- Do not weaken, skip, or delete failing tests.
- Before commit, verify tab ID, pane ID, location, scope, ordinary query, and explicit tag query against the captured search context.
- Report UI automation that cannot be executed as manual verification required, never as passed.

---

### Task 1: Isolate the Path Field from AppKit's Shared Field Editor

**Files:**
- Modify: `Tests/MyMacFinderTests/PathInputFieldTests.swift`
- Modify: `Sources/MyMacFinder/UI/ToolbarPathView.swift`
- Verify: `Tests/MyMacFinderTests/FileTableViewReuseTests.swift`
- Verify: `Tests/MyMacFinderTests/ExplorerStoreTests.swift`

**Interfaces:**
- Consumes: `PathInputField.Coordinator.applyTextIfNeeded`, `applyFocusClearIfNeeded`, `NSTextField.currentEditor()`
- Produces: path synchronization and focus clearing that can only mutate the path field's own editor

- [x] Add a window-backed test where another text field owns the shared field editor, call path `applyTextIfNeeded`, and assert the rename editor text remains unchanged.
- [x] Add a window-backed test where another text field owns the editor, call path `applyFocusClearIfNeeded`, and assert the rename editor remains first responder.
- [x] Run `swift test --filter PathInputFieldTests` and verify both tests fail because `activeEditor(for:)` falls back to `window.fieldEditor(false, for:)`.
- [x] Replace `activeEditor(for:)` with exactly `textField.currentEditor()` and retain existing path-field Return handling.
- [x] Run `swift test --filter 'PathInputFieldTests|FileTableViewReuseTests|ExplorerStoreTests'` and verify path editing, inline Return commit, Escape cancel, existing item rename, and new-folder rename tests pass.

### Task 2: Make Recursive Search Bounded, Symlink-Safe, Permission-Tolerant, and Cancellable

**Files:**
- Modify: `Tests/MyMacFinderTests/FileSearchServiceTests.swift`
- Modify: `Sources/MyMacFinder/Services/FileSearchService.swift`

**Interfaces:**
- Consumes: `FileSystemServicing.contentsOfDirectory(at:options:)`, `FileEntry.kind`, `isDirectoryLike`, `isReadable`
- Produces: breadth-first recursive search using an index cursor and explicit root-versus-descendant error policy

- [x] Add a real temporary-directory symlink test proving the symlink entry can match but its external target child cannot.
- [x] Add deterministic fake-filesystem tests for descendant `.permissionDenied`, root `.permissionDenied`, unreadable directory entries, and `CancellationError` propagation.
- [x] Run `swift test --filter FileSearchServiceTests` and verify the new tests expose symlink traversal, descendant error abortion, and cancellation swallowing.
- [x] Replace `removeFirst()` with `cursor < directoriesToVisit.count`, enqueue only `isDirectoryLike && isReadable && kind != .symlink`, rethrow cancellation, rethrow root permission errors, and skip only descendant permission errors.
- [x] Re-run `swift test --filter FileSearchServiceTests` and verify all scenarios pass with no leftover temporary paths.

### Task 3: Guard Recursive Search and Finder Tag Commits with Full Context

**Files:**
- Modify: `Tests/MyMacFinderTests/ExplorerSearchStoreTests.swift`
- Modify: `Tests/MyMacFinderTests/ExplorerAdvancedSearchStoreTests.swift`
- Modify: `Tests/MyMacFinderTests/ExplorerSortSettingsTests.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`

**Interfaces:**
- Consumes: tab/pane IDs, pane location, `SearchScope`, `FileEntrySearchCriteria`, pane sort descriptor
- Produces: `SearchContext` snapshots plus monotonically changing `searchGeneration`

- [x] Add controllable non-cooperative search-service tests for stale success, stale `ExplorerError`, stale general error, pane switch, tab switch, and duplicate activation of the already-active pane.
- [x] Add ordinary-query Finder Tag tests for current-folder and recursive scope; assert `includeFinderTags` is true whenever ordinary query or explicit tag query is non-empty.
- [x] Add a recursive-result sort test proving completion uses the latest pane sort and an already-completed result re-sorts immediately.
- [x] Run the three focused test classes and verify the new tests fail against query/scope-only guards.
- [x] Add `SearchContext(generation, tabID, paneID, location, scope, criteria)` and validate all six user-visible context dimensions on success and both error paths before mutating `recursiveSearchResults`, `visibleError`, or `isSearching`.
- [x] Make active-pane changes clear recursive results and reschedule on the new root; make no-op activation return before restarting search/tag population.
- [x] Treat ordinary query or explicit tag query as requiring Finder Tags, keep base listing `includeFinderTags: false`, and populate current-folder tags off-main only when needed.
- [x] Apply the current pane sort at search commit and re-sort cached recursive results in `sortActivePane`/default-sort updates.
- [x] Re-run focused tests and verify stale completions cannot mutate any UI search state.

### Task 4: Roll Back Partial Multi-Item Trash Transactions

**Files:**
- Modify: `Tests/MyMacFinderTests/FileOperationServiceTests.swift`
- Modify: `Sources/MyMacFinder/Services/FileOperationService.swift`

**Interfaces:**
- Consumes: injected `trashItem`, `FileOperationProgressReporter`, `restoreTrashedItems`
- Produces: transaction-level cancellation/error rollback preserving the original error after successful restoration

- [x] Add a simulated-Trash test that cancels after the first moved item and asserts every original exists and simulated Trash is empty.
- [x] Add a cancellation rollback-failure test asserting `.operationFailed` includes the original cancellation and failed restoration path.
- [x] Replace existing real-Trash tests in the touched class with UUID simulated Trash injection.
- [x] Run the two new tests and verify cancellation currently escapes outside the per-item catch, leaving the first item in simulated Trash.
- [x] Wrap all cancellation checks, progress updates, and trash moves in one transaction-level `do/catch`; restore accumulated records in reverse order.
- [x] Rethrow `CancellationError` unchanged after successful rollback, preserve existing Explorer errors after successful rollback, and emit explicit rollback-incomplete `.operationFailed` on restoration failure.
- [x] Re-run `swift test --filter FileOperationServiceTests`.

### Task 5: Canonicalize Filesystem Operations and Protect Case-Only Rename

**Files:**
- Modify: `Tests/MyMacFinderTests/FileOperationServiceTests.swift`
- Modify: `Tests/MyMacFinderTests/FileDropValidatorTests.swift`
- Modify: `Sources/MyMacFinder/Services/FileOperationService.swift`
- Modify: `Sources/MyMacFinder/Services/FileDropValidator.swift`

**Interfaces:**
- Produces: parent-canonicalized leaf URLs, destination canonicalization, same-item checks using `volumeSupportsCaseSensitiveNames` and `fileResourceIdentifier`, and explicit failed-destination cleanup ownership

- [x] Add copy/move/drop tests where destination reaches a source descendant through a parent symlink; verify rejection.
- [x] Add tests proving a directory symlink leaf itself can still be copied/moved without treating its target as the source.
- [x] Add alias-to-same-folder copy test proving keep-both naming rather than replace.
- [x] Add case-only rename success and injected move-failure tests; on failure assert original contents and on-disk entry survive unchanged.
- [x] Run focused tests and verify the canonical-path and case-only failure tests fail.
- [x] Introduce helpers that resolve only parent components for source leaves and fully canonicalize destination folders before self/descendant and same-folder checks.
- [x] Detect case-only same-item rename only when casing differs, case-insensitive names are supported, canonical parents match, and resource identifiers match.
- [x] Bypass conflict resolution for that rename, and pass explicit `removePartialDestination: false` to rollback so a failed move cannot delete the original alias path.
- [x] Keep `removePartialDestination: true` for copy/cross-volume move paths that can own partial output.
- [x] Re-run `FileOperationServiceTests` and `FileDropValidatorTests`.

### Task 6: Reject Stale Pane Loads and Bind History to Pane Identity

**Files:**
- Create: `Tests/MyMacFinderTests/ExplorerPaneLoadRaceTests.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`

**Interfaces:**
- Produces: `[PaneID: UInt64] paneLoadGenerations` and PaneID-based load commits/history updates

- [x] Add a controllable `FileSystemServicing` actor and tests for old load finishing after a newer load, old errors, secondary pane removal during load, active-pane switch during back/forward, and `isLoading` ownership.
- [x] Run `swift test --filter ExplorerPaneLoadRaceTests` and verify stale completion or old index mutation fails.
- [x] Capture target `PaneID` and generation at load start, re-find index by ID after every await, and mutate only when the pane exists and generation is current.
- [x] Capture pane ID in `goBack`/`goForward`; commit history only to that pane after a current successful load.
- [x] Ensure stale success/error/finalization changes none of location, entries, error, search, loading, or history.
- [x] Re-run pane-race tests plus existing navigation/layout/tab/watcher suites.

### Task 7: Make Compound Undo Preflighted and Transactional

**Files:**
- Modify: `Tests/MyMacFinderTests/ExplorerUndoCommandTests.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`

**Interfaces:**
- Produces: ordered undo move plan, simulated preflight state, completed-move journal, reverse rollback, and shared case-only identity exception

- [x] Add a compound Undo preflight test where a later replacement source is absent and assert no earlier filesystem mutation starts.
- [x] Add a TOCTOU test that removes a later source after preflight and asserts earlier completed moves are rolled back.
- [x] Add a rollback-failure test asserting a rollback-incomplete error and original action retention.
- [x] Add case-only rename Undo test asserting the physical directory entry casing returns to the original spelling.
- [x] Run `swift test --filter ExplorerUndoCommandTests` and verify failures.
- [x] Flatten compound actions into an ordered restore plan, preflight against a simulated path state, and allow the case-only destination exception only when all specified casing, parent, volume, and resource-identifier conditions hold.
- [x] Execute planned moves while recording each completion; on failure rollback the journal in reverse and surface rollback-incomplete details.
- [x] Reinsert the original undo action after preflight, execution, cancellation, or rollback failure.
- [x] Use the same case-only identity predicate in preflight and actual restore.
- [x] Re-run Undo and file-operation focused suites.

### Task 8: Review, Verify, Bundle, Isolated QA, Install, and Report

**Files:**
- Modify: `README.md` only for verified current behavior and final test count
- Create: a dated QA report under `docs/qa/` if manual-only gaps remain

- [x] Review the full diff specifically for data loss, symlink bypass, hard-link false positives, stale async mutation, and rollback incompleteness; fix Critical/Important findings and repeat review.
- [x] Scan modified production files for `try!`, `as!`, force unwraps, `fatalError`, empty catches, hidden `try?`, stale indexes after `await`, missing canonicalization, and original-file deletion during rollback.
- [x] Run `swift build -Xswiftc -warnings-as-errors`.
- [x] Run `swift test --enable-code-coverage` and record exact test/failure counts.
- [x] Run `git diff --check`.
- [x] Run `./scripts/build_app.sh --configuration release`, `./scripts/verify-app-icon.sh`, `codesign --verify --deep --strict --verbose=2 build/MyMacFinder.app`, `./scripts/package_personal.sh`, and `unzip -t dist/MyMacFinder-personal-mac.zip`.
- [x] Copy the release app to a UUID staging path with a QA bundle identifier and isolated defaults namespace, ad-hoc sign it, launch it, confirm PID/executable path and no immediate crash, and perform every feasible non-destructive UI flow.
- [x] If Accessibility automation is unavailable, record rename/keyboard/context-menu flows as manual verification required rather than passed.
- [x] Install only after all executable checks pass: quit the app, verify staging signature/hash, move existing `/Applications/MyMacFinder.app` to a UUID backup, atomically install staging, verify installed hash/signature/path/PID, then trash backup and remove staging; restore backup immediately on any failure.
- [x] Before commit, compare captured and current tab, pane, location, scope, ordinary query, and explicit tag query behavior in regression tests.
- [x] Update README from fresh evidence, commit once without pushing, and report branch/commit state plus the requested A-F completion matrix.
