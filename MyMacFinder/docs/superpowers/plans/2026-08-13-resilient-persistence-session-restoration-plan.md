# Resilient Persistence and Session Restoration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Preserve unreadable settings/sidebar/session data and restore valid tabs, panes, and locations safely across launches.

**Architecture:** Convert persisted stores to explicit throwing contracts, keep independent recovery state in `ExplorerStore`, and add a bounded versioned session snapshot that excludes transient and file-operation state. Restore snapshots before the first directory load, validate locations asynchronously, and debounce later snapshot writes with an explicit lifecycle flush.

**Tech Stack:** Swift 6.1, SwiftUI, AppKit, Foundation, XCTest, Swift Package Manager, ZIPFoundation, macOS 15+

## Global Constraints

- Keep Swift 6.1, macOS 15+, SPM, and ZIPFoundation dependency versions unchanged.
- Do not change file-operation, Undo ownership, archive extraction, symlink, or Trash behavior.
- Use only UUID-scoped `FileManager.default.temporaryDirectory` paths in tests and remove the exact paths created.
- Preserve unreadable UserDefaults bytes until an explicit successful reset.
- Write every behavioral test before production code and observe the expected failure.
- Do not persist search queries, selection, history, Undo, clipboard, progress, rename, or error state.
- Do not push automatically.

---

### Task 1: Make settings and sidebar persistence failures explicit

**Files:**
- Modify: `Sources/MyMacFinder/Services/ExplorerSettingsStore.swift`
- Modify: `Sources/MyMacFinder/Services/SidebarFavoritesStore.swift`
- Modify: `Tests/MyMacFinderTests/ExplorerSettingsStoreTests.swift`
- Modify: `Tests/MyMacFinderTests/SidebarFavoritesStoreTests.swift`

**Interfaces:**
- Produces: `func load() throws -> Value`, `func save(_:) throws`, and `func reset() throws` on both persistence protocols.
- Produces: `ExplorerSettings.restorePreviousSession: Bool` with migration default `true`.

- [x] **Step 1: Add failing store tests**

Add tests that corrupt each UserDefaults value, assert `load()` throws, assert the original bytes are unchanged after load, and verify `reset()` removes only the configured key. Add an older-settings decode test that expects `restorePreviousSession == true`.

- [x] **Step 2: Run focused tests and verify the expected failures**

Run:

```bash
swift test --filter 'ExplorerSettingsStoreTests|SidebarFavoritesStoreTests'
```

Expected: compile/test failure because the protocols are non-throwing, reset is absent, and corrupt data currently returns defaults.

- [x] **Step 3: Implement throwing stores without mutation on decode failure**

Change the contracts to:

```swift
public protocol ExplorerSettingsStoring: AnyObject {
    func load() throws -> ExplorerSettings
    func save(_ settings: ExplorerSettings) throws
    func reset() throws
}

public protocol SidebarFavoritesStoring: AnyObject {
    func load() throws -> SidebarState
    func save(_ state: SidebarState) throws
    func reset() throws
}
```

Missing data still returns the default value. Decode errors are rethrown. `reset()` removes only the configured key. Add `restorePreviousSession` to `ExplorerSettings`, defaulting to `true` in both initializers.

- [x] **Step 4: Update test stores to the throwing signatures**

Update all in-memory `ExplorerSettingsStoring` and `SidebarFavoritesStoring` conformers under `Tests/MyMacFinderTests` with `throws` signatures and no-op `reset()` implementations. Do not change their recorded-state assertions.

- [x] **Step 5: Run focused and dependent tests**

```bash
swift test --filter 'ExplorerSettingsStoreTests|SidebarFavoritesStoreTests|ExplorerLayoutSettingsTests|ExplorerSidebarStoreTests'
```

Expected: all selected tests pass.

### Task 2: Add a bounded, versioned session snapshot store

**Files:**
- Create: `Sources/MyMacFinder/Domain/ExplorerSessionSnapshot.swift`
- Create: `Sources/MyMacFinder/Services/ExplorerSessionStore.swift`
- Create: `Tests/MyMacFinderTests/ExplorerSessionStoreTests.swift`

**Interfaces:**
- Produces: `ExplorerSessionSnapshot`, `ExplorerSessionTab`, and `ExplorerSessionPane` Codable value types.
- Produces: `ExplorerSessionStoring.load/save/reset` and `UserDefaultsExplorerSessionStore`.
- Consumes: `PaneLocation`, `EntrySortDescriptor`, `EntryGroupDescriptor`, and `ExplorerPaneMode`.

- [x] **Step 1: Add failing snapshot/store tests**

Cover missing data, valid round-trip, corrupt-byte preservation, payload size rejection, reset scope, clamped active indices, empty tab/pane repair, maximum two panes, and reconstruction with fresh runtime IDs.

- [x] **Step 2: Run the new tests and verify missing-type failures**

```bash
swift test --filter ExplorerSessionStoreTests
```

Expected: compile failure because session snapshot and store types do not exist.

- [x] **Step 3: Implement minimal session domain values**

Use stable Codable fields only:

```swift
public struct ExplorerSessionPane: Codable, Equatable, Sendable {
    public var location: PaneLocation
    public var sort: EntrySortDescriptor
    public var group: EntryGroupDescriptor?
}

public struct ExplorerSessionTab: Codable, Equatable, Sendable {
    public var panes: [ExplorerSessionPane]
    public var activePaneIndex: Int
}

public struct ExplorerSessionSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var tabs: [ExplorerSessionTab]
    public var activeTabIndex: Int
}
```

Provide normalization and conversion helpers that cap tabs at 20 and panes at two, create at least one fallback pane, clamp indices, and regenerate runtime IDs.

- [x] **Step 4: Implement the bounded UserDefaults session store**

Reject payloads larger than 1 MiB before JSON decode. Do not mutate bytes on load failure. `reset()` removes only the session key.

- [x] **Step 5: Run the new tests**

```bash
swift test --filter ExplorerSessionStoreTests
```

Expected: all session store tests pass.

### Task 3: Block unsafe automatic persistence and provide explicit recovery

**Files:**
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Create: `Tests/MyMacFinderTests/ExplorerPersistenceRecoveryTests.swift`
- Modify: existing test-store conformers as required

**Interfaces:**
- Consumes: throwing settings/sidebar/session stores.
- Produces: `settingsPersistenceErrorMessage`, `sidebarPersistenceErrorMessage`, `sessionPersistenceErrorMessage`.
- Produces: `resetSavedSettings()`, `resetSavedSidebar()`, and `resetSavedSession()`.

- [x] **Step 1: Add failing recovery tests**

Use injected stores to prove: corrupt load uses safe in-memory defaults without calling save; later setting/sidebar changes remain blocked; one injected save failure blocks repeated automatic writes; failed reset preserves the warning; successful reset clears the warning and establishes a writable safe value.

- [x] **Step 2: Run the focused tests and verify failures**

```bash
swift test --filter ExplorerPersistenceRecoveryTests
```

Expected: compile/test failure because ExplorerStore cannot observe persistence failures or reset stores.

- [x] **Step 3: Implement independent persistence recovery state**

Catch each load independently during initialization. Initialize defaults for only the failed area, retain its localized error, and set its write-block flag. Change persistence helpers to catch save errors, set a persistent message, and suppress subsequent automatic writes.

- [x] **Step 4: Implement explicit reset methods**

Each reset first calls the store reset. On success, clear the block, establish the safe value, and save once. On failure, keep the previous in-memory state, warning, and block. Settings reset must preserve the current live UI choices rather than unexpectedly changing the open window.

- [x] **Step 5: Run recovery and existing settings/sidebar tests**

```bash
swift test --filter 'ExplorerPersistenceRecoveryTests|ExplorerSettingsStoreTests|SidebarFavoritesStoreTests|ExplorerLayoutSettingsTests|ExplorerSidebarStoreTests'
```

Expected: all selected tests pass.

### Task 4: Restore and validate the previous workspace

**Files:**
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Create: `Tests/MyMacFinderTests/ExplorerSessionRestorationTests.swift`
- Modify: `Tests/MyMacFinderTests/ExplorerPaneLoadRaceTests.swift`

**Interfaces:**
- Consumes: `ExplorerSessionSnapshot` and `PathStatusChecking`.
- Produces: `restorePreviousSession`, `setRestorePreviousSession(_:)`, `flushSessionPersistence()`.

- [x] **Step 1: Add failing restoration tests**

Cover enabled/disabled restore, tab and dual-pane reconstruction, excluded transient state, invalid filesystem location fallback, unreadable location fallback, missing ZIP host fallback, mixed valid/invalid panes, active index normalization, and stale pane-load completion after restored fallback.

- [x] **Step 2: Run restoration tests and verify failures**

```bash
swift test --filter 'ExplorerSessionRestorationTests|ExplorerPaneLoadRaceTests'
```

Expected: compile/test failure because session restoration APIs and startup validation are absent.

- [x] **Step 3: Load the session snapshot during ExplorerStore initialization**

When restoration is enabled and the session store loads, reconstruct tabs and active state before initial directory loading. When disabled, preserve the stored snapshot and start with the supplied initial URL. Never restore transient tab fields.

- [x] **Step 4: Validate restored locations before initial reload**

Use `PathStatusChecking` for filesystem locations and archive host URLs. Replace only invalid panes with the standardized initial URL. Keep pane IDs stable during the validation pass so existing generation protection remains effective.

- [x] **Step 5: Add a one-time fallback for initial restored load failure**

If the validated restored location still fails its first load, reload that pane at the initial URL once. Do not change unrelated tabs or panes and do not retry indefinitely.

- [x] **Step 6: Run focused restoration/race tests**

```bash
swift test --filter 'ExplorerSessionRestorationTests|ExplorerPaneLoadRaceTests|ExplorerSearchStoreTests|ExplorerAdvancedSearchStoreTests'
```

Expected: all selected tests pass.

### Task 5: Debounce session saves and flush on lifecycle transitions

**Files:**
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Create: `Tests/MyMacFinderTests/ExplorerSessionPersistenceTests.swift`

**Interfaces:**
- Produces: debounced `scheduleSessionPersistence()` and public async `flushSessionPersistence()`.
- Consumes: SwiftUI `scenePhase` transitions.

- [x] **Step 1: Add failing debounce/flush tests**

Inject a recording session store and short debounce interval. Verify rapid tab/pane/location changes coalesce into one latest snapshot, cancellation does not write stale state, disabled restoration does not restore but may keep the latest valid snapshot, blocked session persistence does not retry, and explicit flush writes the current snapshot immediately.

- [x] **Step 2: Run focused tests and verify failures**

```bash
swift test --filter ExplorerSessionPersistenceTests
```

Expected: compile/test failure because scheduling and flush behavior are absent.

- [x] **Step 3: Implement debounced snapshots**

Maintain one cancellable `Task<Void, Never>` on the main actor. Snapshot only tabs, panes, active indices, sort, and group state. Cancel and replace pending writes; validate a monotonically increasing save generation before committing.

- [x] **Step 4: Flush on inactive/background scene phase**

Observe `scenePhase` in the root scene and call `flushSessionPersistence()` when leaving `.active`. Flush cancels the debounce task and writes exactly the current snapshot unless the session store is blocked.

- [x] **Step 5: Run persistence and tab tests**

```bash
swift test --filter 'ExplorerSessionPersistenceTests|ExplorerStoreTests|ExplorerPaneLoadRaceTests'
```

Expected: all selected tests pass.

### Task 6: Add native Settings recovery controls

**Files:**
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Create: `Sources/MyMacFinder/App/SavedDataRecoveryView.swift`
- Create: `Tests/MyMacFinderTests/SavedDataRecoveryViewTests.swift`

**Interfaces:**
- Consumes: restore binding, three optional persistence messages, and three reset actions from `ExplorerStore`.
- Produces: presentation-only recovery rows that are testable without opening a window.

- [x] **Step 1: Add failing presentation tests**

Test that no recovery section appears without errors, each error maps to the correct label and reset action, and multiple failures remain separate. Test the `Restore Previous Session` binding independently.

- [x] **Step 2: Run the new tests and verify failures**

```bash
swift test --filter SavedDataRecoveryViewTests
```

Expected: compile failure because the presentation model/view does not exist.

- [x] **Step 3: Implement the focused Settings view**

Add a `Startup` section with the restore toggle and a conditional `Saved Data Recovery` section. Use native labels and bordered buttons, concise explanatory text, and no nested cards or modal alerts.

- [x] **Step 4: Wire reset actions to ExplorerStore**

Call the three explicit reset methods from Tasks. Do not clear warnings in the view itself.

- [x] **Step 5: Run settings and presentation tests**

```bash
swift test --filter 'SavedDataRecoveryViewTests|PrivacyAccessSettingsViewTests|ExplorerLayoutSettingsTests'
```

Expected: all selected tests pass.

### Task 7: Refresh documentation and verify the complete release

**Files:**
- Modify: `README.md`
- Modify: `docs/qa/2026-08-04-full-feature-audit.md`
- Create: `docs/qa/2026-08-13-persistence-session-restoration-verification.md`

**Interfaces:**
- Documents: recovery behavior, session scope, settings toggle, limitations, test evidence, and manual QA evidence.

- [x] **Step 1: Update documentation**

Document previous-session restoration and recovery controls. Correct the stale archive temporary-artifact limitation in the August 4 audit by linking to the August 8 lifecycle verification instead of claiming it is unimplemented.

- [x] **Step 2: Run static and full automated verification**

```bash
swift build -Xswiftc -warnings-as-errors
swift test --enable-code-coverage
git diff --check
```

Expected: warning-free build, all XCTest tests pass with zero failures, and no whitespace errors.

- [x] **Step 3: Build, sign-check, icon-check, and package**

```bash
./scripts/build_app.sh --configuration release
codesign --verify --deep --strict --verbose=2 build/MyMacFinder.app
./scripts/verify-app-icon.sh
./scripts/package_personal.sh
unzip -t dist/MyMacFinder-personal-mac.zip
```

Expected: release app and personal ZIP are produced and all checks pass.

- [x] **Step 4: Run isolated app QA**

Copy the release app to a UUID-named QA bundle, use an isolated bundle identifier/UserDefaults domain, and use only UUID-scoped temporary directories. Verify: valid session restore; dual-pane/tab restore; invalid path fallback; restore disabled; corrupt settings/sidebar/session warning; no overwrite before Reset; individual Reset; normal navigation, rename, search, Quick Look, and app relaunch; no crash.

- [x] **Step 5: Install with rollback protection**

Quit the existing app, stage the verified bundle at a unique path, compare the executable SHA-256, move the existing `/Applications/MyMacFinder.app` to a unique backup, atomically install the staged app, re-verify signature/hash, launch it, and confirm the PID executable path. Restore the backup immediately on any failure.

- [x] **Step 6: Record evidence and commit**

Write exact counts, hashes, QA paths, cleanup status, and evidence boundaries to the new verification document. Commit source, tests, docs, and generated package metadata only if it is already tracked; do not commit build products or push.
