# MyMacSearch Index Health Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-scope health, durable issues, volume availability, targeted rescan, and on-demand index verification without weakening search availability.

**Architecture:** Migrate the SQLite index to schema version 2, persist operational facts next to scope checkpoints, and keep transient scan state in `IndexCoordinator`. A dedicated health reader combines persisted aggregates with live scope states for a restrained Index Center UI. Volume lifecycle is abstracted behind a testable monitor.

**Tech Stack:** Swift 6, SwiftUI, Observation, SQLite3/FTS5, FSEvents, NSWorkspace, XCTest, macOS 14+.

## Global Constraints

- Keep initial scan + SQLite FTS5 + FSEvents as the core architecture.
- Do not add file-content search, OCR, PDF body search, Spotlight dependence, or file mutation.
- A cancelled or failed rescan must retain the last complete scope generation.
- Offline external and network entries remain searchable and are never silently deleted.
- Health aggregation and verification run off the main actor and never on every search keystroke.
- Do not commit `.build`, `build`, `dist`, or temporary index databases.

---

### Task 1: Schema version 2 and health domain models

**Files:**
- Create: `Sources/MyMacSearchCore/Models/IndexHealthModels.swift`
- Modify: `Sources/MyMacSearchCore/Index/SQLiteIndexWriter.swift`
- Create: `Tests/MyMacSearchCoreTests/SQLiteIndexMigrationTests.swift`
- Test: `Tests/MyMacSearchCoreTests/SQLiteIndexTests.swift`

**Interfaces:**
- Consumes: the existing version 1 `entries`, `entries_fts`, and `scopes` schema.
- Produces: `ScopeIndexState`, `ScopeRuntimeState`, `IndexIssueCategory`, `IndexIssueRecord`, `IndexScopeHealth`, `IndexHealthSnapshot`, and a transactional version 1 to version 2 migration.

- [ ] **Step 1: Write a version 1 migration fixture and failing test**

```swift
func testVersionOneMigrationPreservesEntriesFTSAndCheckpoint() async throws {
    let fixture = try VersionOneIndexFixture(
        scopeID: "home",
        path: "/Users/test/report.swift",
        generation: 7,
        eventID: 42
    )
    defer { fixture.remove() }

    _ = try SQLiteIndexWriter(databaseURL: fixture.databaseURL)

    XCTAssertEqual(try fixture.userVersion(), 2)
    XCTAssertEqual(try fixture.entryPaths(), ["/Users/test/report.swift"])
    XCTAssertEqual(try fixture.ftsMatch("report"), ["/Users/test/report.swift"])
    XCTAssertEqual(try fixture.scopeCheckpoint(), 42)
    XCTAssertTrue(try fixture.hasColumn(table: "scopes", name: "last_completed_scan_at"))
    XCTAssertTrue(try fixture.hasTable("index_issues"))
}
```

- [ ] **Step 2: Run the migration test and confirm RED**

Run: `swift test --filter SQLiteIndexMigrationTests.testVersionOneMigrationPreservesEntriesFTSAndCheckpoint`

Expected: failure because the database remains at user version 1 and health columns do not exist.

- [ ] **Step 3: Add the health models**

```swift
public enum ScopeIndexState: String, Codable, Sendable {
    case scanning, watching, paused, offline, permissionNeeded, error, disabled
}

public struct ScopeRuntimeState: Equatable, Sendable {
    public var state: ScopeIndexState
    public var progress: IndexProgress
    public var message: String?
}

public enum IndexIssueCategory: String, Codable, Sendable {
    case permissionDenied, unavailableRoot, metadataRead, scanFailure
    case droppedEvents, databaseMaintenance
}

public struct IndexIssueRecord: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let scopeID: String
    public let path: String
    public let category: IndexIssueCategory
    public let message: String
    public let firstSeenAt: Date
    public let lastSeenAt: Date
    public let occurrenceCount: Int
    public let resolvedAt: Date?
}
```

Add `IndexScopeHealth` with scope identity, state, availability, entry count, scan/event dates, checkpoint, progress, skip/permission counts, unresolved issue count, and last error. Add `IndexHealthSnapshot` with scope rows, total count, SQLite file sizes, and last verification.

- [ ] **Step 4: Implement transactional schema migration**

Replace the unconditional `PRAGMA user_version = 1` with a version switch. For version 1, execute one transaction containing:

```sql
ALTER TABLE scopes ADD COLUMN last_completed_scan_at REAL;
ALTER TABLE scopes ADD COLUMN last_event_at REAL;
ALTER TABLE scopes ADD COLUMN last_error TEXT;

CREATE TABLE index_issues (
  id INTEGER PRIMARY KEY,
  scope_id TEXT NOT NULL,
  path TEXT NOT NULL,
  category TEXT NOT NULL,
  message TEXT NOT NULL,
  first_seen_at REAL NOT NULL,
  last_seen_at REAL NOT NULL,
  occurrence_count INTEGER NOT NULL DEFAULT 1,
  resolved_at REAL,
  UNIQUE(scope_id, path, category)
);

CREATE INDEX idx_index_issues_unresolved
ON index_issues(scope_id, resolved_at, last_seen_at DESC);

CREATE INDEX idx_entries_name_sort ON entries(search_name, id);
CREATE INDEX idx_entries_path_sort ON entries(search_path, id);
CREATE INDEX idx_entries_modified_sort ON entries(modified_at, id);
CREATE INDEX idx_entries_size_sort ON entries(size_bytes, id);
CREATE INDEX idx_entries_kind_name_sort ON entries(kind, search_name, id);

PRAGMA user_version = 2;
```

Fresh databases create the final version 2 schema directly. Versions greater than 2 fail with `SQLiteIndexError.invalidData` instead of being downgraded.

- [ ] **Step 5: Run migration and existing index tests**

Run: `swift test --filter SQLiteIndexMigrationTests && swift test --filter SQLiteIndexTests`

Expected: all migration, FTS, checkpoint, upsert, delete, and generation-pruning tests pass.

- [ ] **Step 6: Commit the migration**

```bash
git add MyMacSearch/Sources/MyMacSearchCore/Models/IndexHealthModels.swift \
  MyMacSearch/Sources/MyMacSearchCore/Index/SQLiteIndexWriter.swift \
  MyMacSearch/Tests/MyMacSearchCoreTests/SQLiteIndexMigrationTests.swift \
  MyMacSearch/Tests/MyMacSearchCoreTests/SQLiteIndexTests.swift
git commit -m "feat: migrate MyMacSearch index health schema"
```

### Task 2: Persist timestamps and coalesced index issues

**Files:**
- Modify: `Sources/MyMacSearchCore/Index/IndexWriting.swift`
- Modify: `Sources/MyMacSearchCore/Index/SQLiteIndexWriter.swift`
- Create: `Tests/MyMacSearchCoreTests/SQLiteIndexIssueTests.swift`
- Modify: `Tests/MyMacSearchAppSupportTests/IndexCoordinatorTests.swift`

**Interfaces:**
- Consumes: scan completion, event checkpoints, and `ScanIssue` values.
- Produces: dated scan/event persistence plus coalesced and resolvable issue records.

- [ ] **Step 1: Write failing issue-coalescing tests**

```swift
func testRepeatedIssueCoalescesAndSuccessfulScanResolvesIt() async throws {
    let fixture = try TemporaryIndexFixture()
    defer { fixture.remove() }
    let first = Date(timeIntervalSince1970: 100)
    let second = Date(timeIntervalSince1970: 200)

    try await fixture.writer.recordIssue(
        scopeID: "home", path: "/private", category: .permissionDenied,
        message: "Permission denied", occurredAt: first
    )
    try await fixture.writer.recordIssue(
        scopeID: "home", path: "/private", category: .permissionDenied,
        message: "Permission denied", occurredAt: second
    )

    var issues = try fixture.issueRows(scopeID: "home")
    XCTAssertEqual(issues.count, 1)
    XCTAssertEqual(issues[0].occurrenceCount, 2)
    XCTAssertEqual(issues[0].lastSeenAt, second)

    try await fixture.writer.resolveIssues(scopeID: "home", resolvedAt: second)
    issues = try fixture.issueRows(scopeID: "home")
    XCTAssertNotNil(issues[0].resolvedAt)
}
```

- [ ] **Step 2: Run the issue test and confirm RED**

Run: `swift test --filter SQLiteIndexIssueTests`

Expected: compile failure because issue persistence methods do not exist.

- [ ] **Step 3: Extend the writing boundary**

```swift
public protocol IndexWriting: Sendable {
    func completeScopeScan(
        scopeID: String, generation: Int64, completedAt: Date
    ) async throws
    func updateEventCheckpoint(
        scopeID: String, eventID: UInt64, occurredAt: Date
    ) async throws
    func recordIssue(
        scopeID: String, path: String, category: IndexIssueCategory,
        message: String, occurredAt: Date
    ) async throws
    func resolveIssues(scopeID: String, resolvedAt: Date) async throws
}
```

Keep existing begin, upsert, and delete methods unchanged. Update test writers with exact operation records including the supplied timestamps.

- [ ] **Step 4: Implement issue upsert and resolution**

Use `INSERT ... ON CONFLICT(scope_id, path, category) DO UPDATE` to update message, last-seen time, increment occurrence count, and clear `resolved_at`. Resolve unresolved rows for a scope only after a completed scan. Update scope scan/event timestamps in the same transactions as their corresponding generation/checkpoint changes.

- [ ] **Step 5: Run focused persistence and coordinator tests**

Run: `swift test --filter SQLiteIndexIssueTests && swift test --filter IndexCoordinatorTests`

Expected: all tests pass and failed scans do not resolve existing issues.

- [ ] **Step 6: Commit persistence**

```bash
git add MyMacSearch/Sources/MyMacSearchCore/Index \
  MyMacSearch/Tests/MyMacSearchCoreTests/SQLiteIndexIssueTests.swift \
  MyMacSearch/Tests/MyMacSearchAppSupportTests/IndexCoordinatorTests.swift
git commit -m "feat: persist MyMacSearch index issues"
```

### Task 3: Per-scope states and targeted rescan

**Files:**
- Modify: `Sources/MyMacSearchAppSupport/IndexCoordinator.swift`
- Modify: `Tests/MyMacSearchAppSupportTests/IndexCoordinatorTests.swift`

**Interfaces:**
- Consumes: configured `IndexScope` values and scan/watcher outcomes.
- Produces: `scopeStates`, derived global status, `rescan(scopeID:)`, and a coalesced single-scan queue.

- [ ] **Step 1: Write failing mixed-state and rescan tests**

```swift
@MainActor
func testTargetedRescanTouchesOnlyRequestedScopeAndPreservesOthers() async throws {
    let scanner = ScopeRecordingScanner()
    let coordinator = makeCoordinator(scanner: scanner)
    coordinator.start(scopes: [homeScope, downloadsScope])
    try await eventually { coordinator.status == .watching }

    coordinator.rescan(scopeID: downloadsScope.id)
    try await eventually { await scanner.scanCount(for: downloadsScope.id) == 2 }

    XCTAssertEqual(await scanner.scanCount(for: homeScope.id), 1)
    XCTAssertEqual(coordinator.scopeStates[homeScope.id]?.state, .watching)
    XCTAssertEqual(coordinator.scopeStates[downloadsScope.id]?.state, .watching)
}
```

Also add a test where one permission-denied scope becomes `.permissionNeeded` while another remains `.watching`, and a test where duplicate rescan requests produce one queued rescan.

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `swift test --filter IndexCoordinatorTests`

Expected: compile failure for missing `scopeStates` and `rescan(scopeID:)`.

- [ ] **Step 3: Implement the scope state machine**

Add observable state:

```swift
public private(set) var scopeStates: [String: ScopeRuntimeState] = [:]
private var pendingRescanScopeIDs: Set<String> = []
private var activeScanScopeID: String?

public func rescan(scopeID: String) {
    guard scopesByID[scopeID]?.isEnabled == true else { return }
    pendingRescanScopeIDs.insert(scopeID)
    startNextScanIfNeeded()
}
```

Run one full scan at a time. Update only the active scope's progress. Derive global `IndexStatus` in this priority order: initial scan if any scope is scanning, error only for a database/global failure, permission needed if no scope is healthy and at least one needs permission, watching if any scope watches, otherwise paused.

- [ ] **Step 4: Persist issues from scan and event paths**

Map `ScanIssue.Category.permissionDenied` to `.permissionDenied` and other scan failures to `.metadataRead` or `.scanFailure`. Record dropped FSEvents before scheduling reconciliation. A successful completed scope scan resolves previous issues for that scope.

- [ ] **Step 5: Run coordinator, scanner, and watcher tests**

Run: `swift test --filter IndexCoordinatorTests && swift test --filter FileScannerTests && swift test --filter FSEventsWatcherLifecycleTests`

Expected: all tests pass, including pause/resume and dropped-event reconciliation.

- [ ] **Step 6: Commit scope state support**

```bash
git add MyMacSearch/Sources/MyMacSearchAppSupport/IndexCoordinator.swift \
  MyMacSearch/Tests/MyMacSearchAppSupportTests/IndexCoordinatorTests.swift
git commit -m "feat: add per-scope index state and rescan"
```

### Task 4: Volume identity and offline lifecycle

**Files:**
- Modify: `Sources/MyMacSearchAppSupport/SearchSettings.swift`
- Create: `Sources/MyMacSearchAppSupport/VolumeAvailabilityMonitor.swift`
- Modify: `Sources/MyMacSearchApp/AppModel.swift`
- Create: `Tests/MyMacSearchAppSupportTests/VolumeAvailabilityMonitorTests.swift`
- Modify: `Tests/MyMacSearchAppSupportTests/SearchSettingsTests.swift`

**Interfaces:**
- Consumes: root URLs, stored expected volume UUIDs, and workspace mount notifications.
- Produces: availability updates that mark scopes offline without deleting cached entries.

- [ ] **Step 1: Write failing identity and settings-compatibility tests**

```swift
func testMissingOptionalVolumeIdentityDecodesFromVersionOneSettings() throws {
    let settings = try JSONDecoder().decode(SearchSettings.self, from: versionOneJSON)
    XCTAssertNil(settings.scopes[0].expectedVolumeUUID)
}

func testDifferentVolumeAtSameMountPathRequiresExplicitRecovery() async throws {
    let monitor = VolumeAvailabilityMonitor(client: FakeVolumeClient(uuid: "new"))
    let state = await monitor.availability(
        rootPath: "/Volumes/Work", expectedVolumeUUID: "old"
    )
    XCTAssertEqual(state, .identityMismatch(actualUUID: "new"))
}
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `swift test --filter VolumeAvailabilityMonitorTests && swift test --filter SearchSettingsTests`

Expected: compile failure for the missing identity field and monitor.

- [ ] **Step 3: Add settings-compatible volume identity**

Add `expectedVolumeUUID: String?` to `SearchScopeSetting`. Populate it when a scope is chosen using `.volumeUUIDStringKey`. Keep the settings schema readable from existing JSON by decoding a missing key as `nil`; update last-good recovery tests.

- [ ] **Step 4: Implement the monitor behind a protocol**

```swift
public enum VolumeAvailability: Equatable, Sendable {
    case available
    case offline
    case identityMismatch(actualUUID: String?)
}

public protocol VolumeAvailabilityChecking: Sendable {
    func availability(rootPath: String, expectedVolumeUUID: String?) async -> VolumeAvailability
}
```

The production monitor observes `NSWorkspace.didMountNotification` and `didUnmountNotification`, debounces duplicate notifications, and reports affected scope IDs on the main actor. Internal local roots without a stored UUID use reachability only.

- [ ] **Step 5: Integrate offline state without pruning rows**

On offline or identity mismatch, stop or omit watching that scope, set its runtime state, and retain its SQLite rows. On a matching remount, enqueue targeted reconciliation before returning to Watching. Do not call `IndexWriting.delete` for an unavailable root.

- [ ] **Step 6: Run settings, coordinator, and volume tests**

Run: `swift test --filter SearchSettingsTests && swift test --filter VolumeAvailabilityMonitorTests && swift test --filter IndexCoordinatorTests`

Expected: all tests pass and offline scopes keep their existing entries.

- [ ] **Step 7: Commit volume lifecycle support**

```bash
git add MyMacSearch/Sources/MyMacSearchAppSupport \
  MyMacSearch/Sources/MyMacSearchApp/AppModel.swift \
  MyMacSearch/Tests/MyMacSearchAppSupportTests
git commit -m "feat: track MyMacSearch volume availability"
```

### Task 5: Health reader, verification, and view model

**Files:**
- Create: `Sources/MyMacSearchCore/Index/IndexHealthReading.swift`
- Create: `Sources/MyMacSearchCore/Index/SQLiteIndexHealthReader.swift`
- Create: `Sources/MyMacSearchCore/Index/SQLiteIndexVerifier.swift`
- Create: `Sources/MyMacSearchAppSupport/IndexHealthViewModel.swift`
- Create: `Tests/MyMacSearchCoreTests/SQLiteIndexHealthReaderTests.swift`
- Create: `Tests/MyMacSearchCoreTests/SQLiteIndexVerifierTests.swift`
- Create: `Tests/MyMacSearchAppSupportTests/IndexHealthViewModelTests.swift`

**Interfaces:**
- Consumes: schema version 2 persisted data and live `scopeStates`.
- Produces: cached `IndexHealthSnapshot`, bounded issue pages, and explicit verification results.

- [ ] **Step 1: Write failing health aggregation tests**

```swift
func testSnapshotAggregatesCountsByScopeAndFileSizes() async throws {
    let fixture = try PopulatedHealthFixture()
    defer { fixture.remove() }
    let snapshot = try await fixture.reader.snapshot(liveStates: fixture.liveStates)

    XCTAssertEqual(snapshot.totalEntryCount, 3)
    XCTAssertEqual(snapshot.scopes.first { $0.scopeID == "home" }?.entryCount, 2)
    XCTAssertGreaterThan(snapshot.databaseBytes, 0)
}
```

Add verifier tests for `quick_check = ok`, FTS integrity success, and a deliberately malformed fixture producing a typed failure rather than a crash.

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `swift test --filter SQLiteIndexHealthReaderTests && swift test --filter SQLiteIndexVerifierTests`

Expected: compile failure because health reader and verifier do not exist.

- [ ] **Step 3: Define the read and verify boundaries**

```swift
public protocol IndexHealthReading: Sendable {
    func snapshot(liveStates: [String: ScopeRuntimeState]) async throws -> IndexHealthSnapshot
    func issues(scopeID: String?, unresolvedOnly: Bool, limit: Int) async throws -> [IndexIssueRecord]
}

public protocol IndexVerifying: Sendable {
    func verify() async throws -> IndexVerificationResult
}
```

Clamp issue limits to 1...500. Compute scope counts with one grouped query. Read database/WAL/SHM sizes using file metadata after SQLite statements finish.

- [ ] **Step 4: Implement explicit verification**

Run `PRAGMA quick_check`, the FTS5 integrity command, entry/FTS row consistency checks, and schema-version validation on the reader actor. Return a structured result with start/end dates and individual checks. Never invoke verification from `search()`.

- [ ] **Step 5: Implement stale-result-safe view model loading**

`IndexHealthViewModel` uses a generation counter and cancellable tasks, mirroring `SearchViewModel`, so a slow old refresh cannot replace a newer snapshot. Cache a successful snapshot for one second and expose `isRefreshing`, `verification`, and `errorMessage` separately.

- [ ] **Step 6: Run core and view-model tests**

Run: `swift test --filter SQLiteIndexHealthReaderTests && swift test --filter SQLiteIndexVerifierTests && swift test --filter IndexHealthViewModelTests`

Expected: all tests pass, including stale refresh suppression.

- [ ] **Step 7: Commit health services**

```bash
git add MyMacSearch/Sources/MyMacSearchCore/Index \
  MyMacSearch/Sources/MyMacSearchAppSupport/IndexHealthViewModel.swift \
  MyMacSearch/Tests
git commit -m "feat: add MyMacSearch index health services"
```

### Task 6: Index Center and status integration

**Files:**
- Create: `Sources/MyMacSearchApp/Views/IndexCenterView.swift`
- Modify: `Sources/MyMacSearchApp/Views/SearchResultsTable.swift`
- Modify: `Sources/MyMacSearchApp/Views/SearchRootView.swift`
- Modify: `Sources/MyMacSearchApp/AppModel.swift`
- Modify: `Sources/MyMacSearchApp/MyMacSearchApp.swift`
- Modify: `Tests/MyMacSearchAppSupportTests/NativeInterfaceSourceTests.swift`

**Interfaces:**
- Consumes: `IndexHealthViewModel`, coordinator scope states, rescan, verification, and permission actions.
- Produces: a compact Index Center window plus location state badges and offline result affordances.

- [ ] **Step 1: Add failing native interface contract tests**

```swift
func testIndexCenterExposesHealthWithoutReplacingSearchTool() throws {
    let app = try allAppSource()
    XCTAssertTrue(app.contains("IndexCenterView"))
    XCTAssertTrue(app.contains("Verify Index"))
    XCTAssertTrue(app.contains("Rescan"))
    XCTAssertTrue(app.contains("Indexed Entries"))
    XCTAssertTrue(app.contains("Last Completed Scan"))
    XCTAssertTrue(try source("Views/SearchRootView.swift").contains("SearchResultsTable"))
}
```

- [ ] **Step 2: Run the interface test and confirm RED**

Run: `swift test --filter NativeInterfaceSourceTests.testIndexCenterExposesHealthWithoutReplacingSearchTool`

Expected: failure because Index Center does not exist.

- [ ] **Step 3: Wire services in `AppModel`**

Create the health reader, verifier, and `IndexHealthViewModel` beside the existing writer and reader. Add actions for opening Index Center, refreshing, verifying, rescanning one scope, and rescanning all enabled scopes. Service construction failure that affects health only must not clear the search reader.

- [ ] **Step 4: Build the restrained Index Center UI**

Use a `Table` for scope rows and a detail section for issues. Show status, path, count, last scan, last event, and issues. Buttons are contextual: Rescan, Open Privacy Settings, Refresh, and Verify Index. Do not use dashboard cards or charts.

- [ ] **Step 5: Integrate sidebar and status bar**

Add a small state symbol beside each location. Make the status text/button open Index Center. Show `Offline` as a muted badge for cached rows whose scope is unavailable. Keep the existing search field and results as the first screen.

- [ ] **Step 6: Build with strict concurrency and run tests**

Run:

```bash
swift test
swift build -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
```

Expected: all tests pass and both builds emit no warnings.

- [ ] **Step 7: Commit Index Center**

```bash
git add MyMacSearch/Sources/MyMacSearchApp MyMacSearch/Tests/MyMacSearchAppSupportTests
git commit -m "feat: add MyMacSearch Index Center"
```

### Task 7: Performance, live QA, documentation, and package

**Files:**
- Modify: `Tests/MyMacSearchCoreTests/LargeIndexRegressionTests.swift`
- Modify: `Tests/MyMacSearchCoreTests/IndexPerformanceTests.swift`
- Modify: `README.md`
- Create: `docs/qa/2026-08-14-index-health-verification.md`
- Modify: `../downloads/MyMacSearch/MyMacSearch-personal-mac.zip`

**Interfaces:**
- Consumes: the completed V1.1A index-health implementation.
- Produces: evidence for one-million-row health performance, live scope transitions, and a verified personal installer.

- [ ] **Step 1: Add health performance assertions**

Populate at least three scopes and 100,000 entries, then assert a health snapshot returns correct counts without touching entry rows individually. Extend the opt-in million benchmark to measure Index Center snapshot time with a target below 250 ms.

- [ ] **Step 2: Run all automated verification**

```bash
swift test
MYMACSEARCH_RUN_MILLION_BENCHMARK=1 swift test -c release --filter IndexPerformanceTests
swift build -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
```

- [ ] **Step 3: Run isolated live QA**

Use an isolated QA home and app-support directory. Verify healthy local scopes, permission-denied descendants, Pause/Resume, targeted rescan, issue display, Verify Index, external-volume offline state, matching remount reconciliation, and mismatched volume refusal. Confirm normal search remains available while Index Center refreshes.

- [ ] **Step 4: Package and verify installation**

```bash
MyMacSearch/scripts/package-personal.sh
MyMacSearch/scripts/check-distribution.sh
codesign --verify --deep --strict --verbose=2 /Applications/MyMacSearch.app
git diff --check
```

Compare packaged and installed executable SHA-256 values and record bundle metadata and verification boundaries.

- [ ] **Step 5: Commit release evidence**

```bash
git add MyMacSearch/README.md MyMacSearch/docs/qa \
  downloads/MyMacSearch/MyMacSearch-personal-mac.zip
git commit -m "release: verify MyMacSearch index health"
```
