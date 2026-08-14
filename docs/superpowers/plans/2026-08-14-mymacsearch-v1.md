# MyMacSearch V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, test, package, and install a native macOS filename/path search utility backed by a user-approved SQLite FTS5 index and FSEvents updates.

**Architecture:** Add a Swift 6 package with `MyMacSearchCore`, `MyMacSearchAppSupport`, and `MyMacSearchApp` targets. Core owns policies, parsing, SQLite, scanning, and event planning; AppSupport owns coordinated state and macOS adapters; the executable owns the SwiftUI/AppKit interface. Add only the minimum MyMacFinder external-folder routing required for the requested integration.

**Tech Stack:** Swift 6, SwiftUI, AppKit, QuickLookUI, Carbon hot keys, Foundation, CoreServices FSEvents, system SQLite3/FTS5, XCTest, Swift Package Manager, shell packaging scripts.

## Global Constraints

- Minimum supported system is macOS 14.0.
- Use system `libsqlite3`; add no third-party SQLite or search dependency.
- V1 indexes metadata only: name, path, extension, kind, size, and modification date.
- Do not implement file content, OCR, PDF body, archive content, Spotlight-primary, fuzzy, or semantic search.
- Do not follow symlinks or descend into packages; hidden entries are excluded by default.
- Do not preselect external or network volumes.
- Do not add file mutation actions, a menu bar item, login item, helper process, or launch agent.
- Preserve all pre-existing user changes. Never reset the worktree or remove unrelated artifacts.
- Keep `.build`, `DerivedData`, temporary `dist`, caches, and QA fixtures out of commits.
- Every behavior change begins with a failing test, then minimal implementation, focused test, full package test, diff review, and a scoped commit.
- The accepted design is `docs/superpowers/specs/2026-08-14-mymacsearch-design.md`.

---

## File Structure

### MyMacSearchCore

- `MyMacSearch/Package.swift`: three production targets, two test targets, SQLite link.
- `Sources/MyMacSearchCore/Models/IndexModels.swift`: entries, scopes, progress, states, search pages, cursors.
- `Sources/MyMacSearchCore/Models/SearchQuery.swift`: parsed terms, filters, date ranges, parser errors.
- `Sources/MyMacSearchCore/Search/SearchQueryParser.swift`: quoting and supported filter grammar.
- `Sources/MyMacSearchCore/Search/FileKindClassifier.swift`: deterministic kind mapping.
- `Sources/MyMacSearchCore/Index/SQLiteConnection.swift`: checked SQLite handle, statements, binds, errors.
- `Sources/MyMacSearchCore/Index/FTS5CapabilityProbe.swift`: in-memory FTS5/trigram functional probe.
- `Sources/MyMacSearchCore/Index/SQLiteIndexWriter.swift`: schema, scopes, batches, deletion, generations.
- `Sources/MyMacSearchCore/Index/SQLiteIndexReader.swift`: ranked, filtered, paginated search.
- `Sources/MyMacSearchCore/Scanning/IndexingPolicy.swift`: root, hidden, package, symlink, and exclusion decisions.
- `Sources/MyMacSearchCore/Scanning/FileMetadataClient.swift`: injectable filesystem metadata boundary.
- `Sources/MyMacSearchCore/Scanning/FileScanner.swift`: cancellable traversal and batches.
- `Sources/MyMacSearchCore/Watching/FileEventModels.swift`: neutral event batches and reconciliation decisions.
- `Sources/MyMacSearchCore/Watching/FSEventsWatcher.swift`: stream lifecycle and checkpoints.
- `Sources/MyMacSearchCore/Watching/FileEventPlanner.swift`: coalescing and rescan fallback.

### MyMacSearchAppSupport and App

- `Sources/MyMacSearchAppSupport/IndexCoordinator.swift`: scan/watch lifecycle and state machine.
- `Sources/MyMacSearchAppSupport/SearchViewModel.swift`: debounced generation-guarded search.
- `Sources/MyMacSearchAppSupport/SearchSettings.swift`: scopes, exclusions, hidden policy, hot key.
- `Sources/MyMacSearchAppSupport/ResultActionService.swift`: Open, Reveal, Copy, Terminal, MyMacFinder.
- `Sources/MyMacSearchAppSupport/GlobalShortcutController.swift`: Carbon registration and conflict errors.
- `Sources/MyMacSearchAppSupport/QuickLookPreviewController.swift`: selection-bound preview session.
- `Sources/MyMacSearchApp/MyMacSearchApp.swift`: app entry, commands, settings, window activation.
- `Sources/MyMacSearchApp/Views/OnboardingView.swift`: scope review before first scan.
- `Sources/MyMacSearchApp/Views/SearchRootView.swift`: search field, sidebar, table, status bar.
- `Sources/MyMacSearchApp/Views/SearchResultsTable.swift`: bounded AppKit table bridge and keyboard routing.
- `Sources/MyMacSearchApp/Views/SettingsView.swift`: scope, exclusion, hidden, and shortcut settings.
- `Sources/MyMacSearchApp/Resources/MyMacSearchInfo.plist`: bundle metadata source.
- `Sources/MyMacSearchApp/Resources/AppIcon.icns`: native app icon.

### Integration, Tests, Packaging, and Docs

- `MyMacFinder/Sources/MyMacFinder/App/ExternalFolderOpenRouter.swift`: validates external directory URLs.
- `MyMacFinder/Sources/MyMacFinder/App/MyMacFinderApp.swift`: routes `.onOpenURL` into ExplorerStore.
- `MyMacFinder/scripts/create-app-bundle.sh`: adds compatibility marker to Info.plist.
- `MyMacFinder/Tests/MyMacFinderTests/ExternalFolderOpenRouterTests.swift`: integration contract.
- `MyMacSearch/Tests/MyMacSearchCoreTests/*.swift`: parser, database, policy, scanner, and watcher coverage.
- `MyMacSearch/Tests/MyMacSearchAppSupportTests/*.swift`: lifecycle, view model, actions, hot key, Quick Look.
- `MyMacSearch/scripts/build-app-bundle.sh`: release app construction and strict signature check.
- `MyMacSearch/scripts/package-personal.sh`: personal ZIP and rollback-safe installer.
- `MyMacSearch/scripts/check-distribution.sh`: quarantine/install/hash simulation.
- `MyMacSearch/README.md`: use, permissions, indexing, syntax, limits, tests, packaging.
- `README.md`: repository app table, run command, structure, platform, and artifact link.
- `downloads/MyMacSearch/MyMacSearch-personal-mac.zip`: approved personal artifact only.
- `MyMacSearch/docs/qa/2026-08-14-release-verification.md`: automated/manual evidence and boundaries.

---

### Task 1: Package, Domain Models, Query Parser, and Kind Mapping

**Files:**
- Create: `MyMacSearch/Package.swift`
- Create: `MyMacSearch/Sources/MyMacSearchCore/Models/IndexModels.swift`
- Create: `MyMacSearch/Sources/MyMacSearchCore/Models/SearchQuery.swift`
- Create: `MyMacSearch/Sources/MyMacSearchCore/Search/SearchQueryParser.swift`
- Create: `MyMacSearch/Sources/MyMacSearchCore/Search/FileKindClassifier.swift`
- Create: `MyMacSearch/Tests/MyMacSearchCoreTests/SearchQueryParserTests.swift`
- Create: `MyMacSearch/Tests/MyMacSearchCoreTests/FileKindClassifierTests.swift`

**Interfaces:**
- Produces: `SearchQueryParser.parse(_:now:calendar:) throws -> SearchQuery`.
- Produces: `FileKindClassifier.kind(name:isDirectory:isPackage:) -> IndexedFileKind`.
- Produces: `IndexedEntry`, `IndexScope`, `IndexProgress`, `IndexStatus`, `SearchPage`, and `SearchCursor` as `Sendable` value types.

- [ ] **Step 1: Write parser and kind-classifier tests**

```swift
@Test func parsesCombinedFilters() throws {
    let query = try SearchQueryParser.parse(
        #"name:"annual report" ext:pdf path:Downloads modified:7d"#,
        now: Date(timeIntervalSince1970: 1_723_593_600),
        calendar: Calendar(identifier: .gregorian)
    )
    #expect(query.nameTerms == ["annual report"])
    #expect(query.extensions == ["pdf"])
    #expect(query.pathTerms == ["downloads"])
    #expect(query.modifiedRange != nil)
}

@Test func classifiesPDFBeforeGenericDocument() {
    #expect(FileKindClassifier.kind(name: "Guide.PDF", isDirectory: false, isPackage: false) == .pdf)
}
```

- [ ] **Step 2: Run tests and confirm the missing-module/type failure**

Run: `swift test --package-path MyMacSearch --filter SearchQueryParserTests`

Expected: FAIL because the package or parser does not exist.

- [ ] **Step 3: Add the manifest, Sendable domain types, finite-state parser, and deterministic kind table**

```swift
public enum SearchQueryParser {
    public static func parse(
        _ input: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> SearchQuery
}

public enum IndexedFileKind: String, CaseIterable, Codable, Sendable {
    case folder, application, pdf, image, video, audio, archive, code, document, other
}
```

Use Swift-side Unicode canonical composition and case/diacritic folding for searchable values. Reject unknown filters, missing values, unterminated quotes, unsupported kinds, and invalid `modified:` values with typed `SearchQueryParseError` cases.

- [ ] **Step 4: Run focused and full package tests**

Run: `swift test --package-path MyMacSearch`

Expected: PASS.

- [ ] **Step 5: Review and commit**

Run: `git diff --check && git diff -- MyMacSearch`

Commit: `feat: add MyMacSearch query domain`

---

### Task 2: SQLite Capability, Schema, Mutation, and Search

**Files:**
- Create: `MyMacSearch/Sources/MyMacSearchCore/Index/SQLiteConnection.swift`
- Create: `MyMacSearch/Sources/MyMacSearchCore/Index/FTS5CapabilityProbe.swift`
- Create: `MyMacSearch/Sources/MyMacSearchCore/Index/SQLiteIndexWriter.swift`
- Create: `MyMacSearch/Sources/MyMacSearchCore/Index/SQLiteIndexReader.swift`
- Create: `MyMacSearch/Tests/MyMacSearchCoreTests/FTS5CapabilityProbeTests.swift`
- Create: `MyMacSearch/Tests/MyMacSearchCoreTests/SQLiteIndexTests.swift`
- Create: `MyMacSearch/Tests/MyMacSearchCoreTests/SQLiteSearchTests.swift`

**Interfaces:**
- Consumes: `IndexedEntry`, `SearchQuery`, `SearchPage`, `SearchCursor` from Task 1.
- Produces: `FTS5CapabilityProbe.verify() throws`.
- Produces: `SQLiteIndexWriter.open(at:)`, `beginScopeScan`, `upsertBatch`, `delete(path:)`, `completeScopeScan`.
- Produces: `SQLiteIndexReader.open(at:)` and `search(query:limit:after:) async throws -> SearchPage`.

- [ ] **Step 1: Write failing functional database tests**

```swift
@Test func updatesAndDeletesFTSRowsTransactionally() async throws {
    let fixture = try TemporaryIndexFixture()
    try await fixture.writer.upsertBatch([.fixture(path: "/tmp/AnnualReport.swift")], scopeID: "home", generation: 1)
    #expect(try await fixture.reader.searchText("report").entries.count == 1)
    try await fixture.writer.delete(path: "/tmp/AnnualReport.swift")
    #expect(try await fixture.reader.searchText("report").entries.isEmpty)
}

@Test func punctuationIsBoundNotInterpolated() async throws {
    let results = try await fixture.reader.search(query: try .parse(#"name:"port.s""#), limit: 200, after: nil)
    #expect(results.entries.map(\.name) == ["Report.swift"])
}
```

- [ ] **Step 2: Run database tests and confirm missing implementation failure**

Run: `swift test --package-path MyMacSearch --filter SQLiteIndexTests`

Expected: FAIL because SQLite index types are undefined.

- [ ] **Step 3: Implement checked SQLite primitives and FTS5 functional probe**

```swift
public enum FTS5CapabilityProbe {
    public static func verify() throws {
        // open :memory:, create fts5(trigram), insert punctuation, run bound MATCH
    }
}
```

Every prepare, bind, step, reset, finalize, transaction, busy-timeout, and close path returns or throws a typed `SQLiteIndexError`. Use `SQLITE_OPEN_FULLMUTEX`, WAL, foreign keys, `synchronous=NORMAL`, and a 2,000 ms busy timeout.

- [ ] **Step 4: Implement versioned schema, triggers, generation-safe mutation, ranking, and keyset pagination**

```sql
CREATE TABLE entries (
  id INTEGER PRIMARY KEY,
  scope_id TEXT NOT NULL,
  path TEXT NOT NULL UNIQUE,
  parent_path TEXT NOT NULL,
  name TEXT NOT NULL,
  search_name TEXT NOT NULL,
  search_path TEXT NOT NULL,
  extension TEXT NOT NULL,
  kind TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  modified_at REAL NOT NULL,
  is_directory INTEGER NOT NULL,
  is_symlink INTEGER NOT NULL,
  is_package INTEGER NOT NULL,
  is_hidden INTEGER NOT NULL,
  device_id INTEGER,
  inode INTEGER,
  scan_generation INTEGER NOT NULL
);
CREATE VIRTUAL TABLE entries_fts USING fts5(search_name, search_path, content='entries', content_rowid='id', tokenize='trigram');
```

Add indexes for scope/path, extension, kind, modification date, normalized name, and parent path. Keep FTS and content rows synchronized in the same transaction. Use bound parameters for all user values.

- [ ] **Step 5: Run focused tests, full tests, and warning-strict build**

Run:

```bash
swift test --package-path MyMacSearch --filter SQLite
swift test --package-path MyMacSearch
swift build --package-path MyMacSearch -Xswiftc -warnings-as-errors
```

Expected: PASS.

- [ ] **Step 6: Review and commit**

Commit: `feat: add SQLite FTS5 search index`

---

### Task 3: Safe Indexing Policy and Cancellable Scanner

**Files:**
- Create: `MyMacSearch/Sources/MyMacSearchCore/Scanning/IndexingPolicy.swift`
- Create: `MyMacSearch/Sources/MyMacSearchCore/Scanning/FileMetadataClient.swift`
- Create: `MyMacSearch/Sources/MyMacSearchCore/Scanning/FileScanner.swift`
- Create: `MyMacSearch/Tests/MyMacSearchCoreTests/IndexingPolicyTests.swift`
- Create: `MyMacSearch/Tests/MyMacSearchCoreTests/FileScannerTests.swift`

**Interfaces:**
- Consumes: `IndexedEntry`, `IndexScope`, `IndexProgress`, and `SQLiteIndexWriter` batch input.
- Produces: `IndexingPolicy.decision(for:root:) -> IndexingDecision`.
- Produces: `FileScanner.scan(scope:generation:onBatch:onProgress:) async throws -> ScanSummary`.

- [ ] **Step 1: Write failing traversal-policy and scanner tests**

```swift
@Test func indexesSymlinkWithoutDescending() async throws {
    let client = MockMetadataClient.tree([.symlink("/scope/link", targetChildren: ["secret.txt"])])
    let summary = try await scanner(client).scan(scope: .fixture("/scope"), generation: 1)
    #expect(summary.entries.map(\.path) == ["/scope/link"])
    #expect(client.enumeratedDirectories == ["/scope"])
}

@Test func permissionFailureIsSkippedAndScanContinues() async throws {
    let summary = try await scanner(.permissionFailureAt("/scope/blocked")).scan(scope: .fixture("/scope"), generation: 1)
    #expect(summary.skippedCount == 1)
    #expect(summary.permissionDeniedCount == 1)
    #expect(summary.completed)
}
```

- [ ] **Step 2: Run scanner tests and confirm failure**

Run: `swift test --package-path MyMacSearch --filter FileScannerTests`

Expected: FAIL because policy and scanner are missing.

- [ ] **Step 3: Implement exact built-in exclusions and injectable metadata reads**

```swift
public enum IndexingDecision: Sendable, Equatable {
    case exclude
    case indexOnly
    case indexAndDescend
}
```

Use no-follow resource values. Exclude `/System`, `/Library`, `~/Library/Caches`, `.git`, `.build`, `node_modules`, and `DerivedData`; treat packages as `indexOnly`; treat symlinks as `indexOnly`; make hidden behavior a separate setting.

- [ ] **Step 4: Implement background breadth-first traversal, 1,000-entry batches, throttled progress, and cancellation boundaries**

Cancellation must be checked at entry, before/after directory enumeration, before metadata reads, before batch delivery, and before completion. Cap retained issues at 500 per scope while keeping exact aggregate counts.

- [ ] **Step 5: Run scanner, full, and warning-strict tests**

Run: `swift test --package-path MyMacSearch && swift build --package-path MyMacSearch -Xswiftc -warnings-as-errors`

Expected: PASS.

- [ ] **Step 6: Review and commit**

Commit: `feat: add cancellable metadata scanner`

---

### Task 4: FSEvents, Scan Handoff, and Index Lifecycle Coordinator

**Files:**
- Create: `MyMacSearch/Sources/MyMacSearchCore/Watching/FileEventModels.swift`
- Create: `MyMacSearch/Sources/MyMacSearchCore/Watching/FSEventsWatcher.swift`
- Create: `MyMacSearch/Sources/MyMacSearchCore/Watching/FileEventPlanner.swift`
- Create: `MyMacSearch/Sources/MyMacSearchAppSupport/IndexCoordinator.swift`
- Create: `MyMacSearch/Tests/MyMacSearchCoreTests/FileEventPlannerTests.swift`
- Create: `MyMacSearch/Tests/MyMacSearchAppSupportTests/IndexCoordinatorTests.swift`

**Interfaces:**
- Consumes: writer, scanner, policy, `IndexStatus`, `IndexProgress`.
- Produces: `FileEventPlanner.plan(events:) -> FileEventPlan`.
- Produces: `@MainActor IndexCoordinator.start()`, `pause()`, `resume()`, `retry(scopeID:)`, and published state.

- [ ] **Step 1: Write failing event-drop, scan-handoff, stale-callback, pause, and resume tests**

```swift
@Test func droppedEventsRequireReconciliation() {
    let plan = FileEventPlanner.plan(events: [.fixture(flags: [.kernelDropped])])
    #expect(plan.requiresFullReconciliation)
    #expect(plan.pathMutations.isEmpty)
}

@Test func eventDuringInitialScanAppliesBeforeWatching() async {
    await harness.startScanAndYield()
    await harness.emit(.created("/scope/new.swift"))
    await harness.finishScan()
    #expect(harness.appliedPaths == ["/scope/new.swift"])
    #expect(harness.status == .watching)
}
```

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --package-path MyMacSearch --filter IndexCoordinatorTests`

Expected: FAIL because watcher and coordinator are undefined.

- [ ] **Step 3: Implement FSEvents context ownership, file flags, event IDs, 250 ms coalescing, and clean stop**

Use retained callback boxes, a dedicated serial queue, explicit stream start failure, generation IDs, and stop/invalidate/release ordering. Do not deliver callbacks from an obsolete generation.

- [ ] **Step 4: Implement bounded scan-time buffering and reconciliation state machine**

Start the watcher/checkpoint before scanning, buffer during the scan, complete the generation, apply buffered events, and only then publish `Watching`. Buffer overflow, wrapped IDs, dropped events, root changes, invalid checkpoints, and reconnect schedule reconciliation.

- [ ] **Step 5: Run all MyMacSearch tests and warning-strict build**

Run: `swift test --package-path MyMacSearch && swift build --package-path MyMacSearch -Xswiftc -warnings-as-errors`

Expected: PASS.

- [ ] **Step 6: Review and commit**

Commit: `feat: maintain index with FSEvents`

---

### Task 5: Search View Model, Settings, and Status Presentation

**Files:**
- Create: `MyMacSearch/Sources/MyMacSearchAppSupport/SearchViewModel.swift`
- Create: `MyMacSearch/Sources/MyMacSearchAppSupport/SearchSettings.swift`
- Create: `MyMacSearch/Tests/MyMacSearchAppSupportTests/SearchViewModelTests.swift`
- Create: `MyMacSearch/Tests/MyMacSearchAppSupportTests/SearchSettingsTests.swift`

**Interfaces:**
- Consumes: `SQLiteIndexReader`, parser, coordinator states, `SearchPage`.
- Produces: `@MainActor SearchViewModel` with query, rows, selection, parserError, searchError, state, and pagination commands.
- Produces: `SearchSettingsStore.load()` and `save(_:)` with atomic last-good preservation.

- [ ] **Step 1: Write failing debounce, stale generation, parser error, pagination, and corrupt-settings tests**

```swift
@Test func slowOldQueryCannotReplaceNewResults() async {
    let harness = SearchHarness(delays: ["old": .milliseconds(200), "new": .zero])
    harness.model.query = "old"
    harness.model.query = "new"
    await harness.finish()
    #expect(harness.model.rows.map(\.name) == ["new.swift"])
}
```

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `swift test --package-path MyMacSearch --filter SearchViewModelTests`

Expected: FAIL because AppSupport search state is missing.

- [ ] **Step 3: Implement 60 ms debounce, generation checks before and after await, selection preservation, and keyset load-more**

Do not clear the last good rows on transient SQLite errors. Parser errors prevent database calls and remain visible beneath the search field.

- [ ] **Step 4: Implement versioned settings with recommended existing roots and explicit external/network opt-in flags**

The first-run flag remains false until the user confirms scopes. Never create missing recommended directories.

- [ ] **Step 5: Run full tests, review, and commit**

Run: `swift test --package-path MyMacSearch && git diff --check`

Commit: `feat: add search and index presentation state`

---

### Task 6: Read-only Actions and MyMacFinder External Folder Integration

**Files:**
- Create: `MyMacSearch/Sources/MyMacSearchAppSupport/ResultActionService.swift`
- Create: `MyMacSearch/Tests/MyMacSearchAppSupportTests/ResultActionServiceTests.swift`
- Create: `MyMacFinder/Sources/MyMacFinder/App/ExternalFolderOpenRouter.swift`
- Modify: `MyMacFinder/Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Modify: `MyMacFinder/scripts/create-app-bundle.sh`
- Create: `MyMacFinder/Tests/MyMacFinderTests/ExternalFolderOpenRouterTests.swift`

**Interfaces:**
- Produces: `@MainActor ResultActionService.perform(_:entry:) async throws`.
- Produces: `ExternalFolderOpenRouter.validate(_:) throws -> URL`.
- Consumes: `ExplorerStore.navigate(to:) async` for a validated directory.
- Adds Info.plist boolean `MyMacFinderSupportsExternalFolderOpen = true`.

- [ ] **Step 1: Write failing action and external-router tests**

```swift
@Test func incompatibleMyMacFinderDoesNotReportSuccess() async {
    let workspace = WorkspaceSpy(bundleInfo: [:])
    await #expect(throws: ResultActionError.incompatibleMyMacFinder) {
        try await service(workspace).perform(.openInMyMacFinder, entry: .fileFixture)
    }
}

@Test func routerRejectsRegularFile() throws {
    #expect(throws: ExternalFolderOpenError.notDirectory) {
        try router.validate(fileFixtureURL)
    }
}
```

- [ ] **Step 2: Run focused tests in both packages and confirm failures**

Run:

```bash
swift test --package-path MyMacSearch --filter ResultActionServiceTests
swift test --package-path MyMacFinder --filter ExternalFolderOpenRouterTests
```

Expected: FAIL because services and router do not exist.

- [ ] **Step 3: Implement existence revalidation and injected NSWorkspace, pasteboard, and Terminal adapters**

Open directories directly, open file parents in Terminal/MyMacFinder, reveal the selected file, and return typed missing-path, missing-app, incompatible-app, and launch-failure errors. Queue index reconciliation after missing-path detection.

- [ ] **Step 4: Implement MyMacFinder `.onOpenURL` directory validation, active-pane navigation, and capability marker**

The handler accepts only file URLs that currently resolve to directories. It does not register MyMacFinder as the default folder application and does not mutate files.

- [ ] **Step 5: Run both full suites and warning-strict builds**

Run:

```bash
swift test --package-path MyMacSearch
swift build --package-path MyMacSearch -Xswiftc -warnings-as-errors
swift test --package-path MyMacFinder
swift build --package-path MyMacFinder -Xswiftc -warnings-as-errors
```

Expected: PASS.

- [ ] **Step 6: Review only approved cross-app files and commit**

Commit: `feat: open search results in MyMacFinder`

---

### Task 7: Global Shortcut, Quick Look, and Native Search UI

**Files:**
- Create: `MyMacSearch/Sources/MyMacSearchAppSupport/GlobalShortcutController.swift`
- Create: `MyMacSearch/Sources/MyMacSearchAppSupport/QuickLookPreviewController.swift`
- Create: `MyMacSearch/Tests/MyMacSearchAppSupportTests/GlobalShortcutControllerTests.swift`
- Create: `MyMacSearch/Tests/MyMacSearchAppSupportTests/QuickLookPreviewControllerTests.swift`
- Create: `MyMacSearch/Sources/MyMacSearchApp/MyMacSearchApp.swift`
- Create: `MyMacSearch/Sources/MyMacSearchApp/Views/OnboardingView.swift`
- Create: `MyMacSearch/Sources/MyMacSearchApp/Views/SearchRootView.swift`
- Create: `MyMacSearch/Sources/MyMacSearchApp/Views/SearchResultsTable.swift`
- Create: `MyMacSearch/Sources/MyMacSearchApp/Views/SettingsView.swift`

**Interfaces:**
- Consumes: coordinator, view model, settings, result actions.
- Produces: `GlobalShortcutController.register(_:) throws`, `unregister()`, callback.
- Produces: Quick Look data source bound to the current selected URL.

- [ ] **Step 1: Write failing shortcut conflict, duplicate-registration, preview generation, and source-wiring tests**

```swift
@Test func replacingShortcutUnregistersPreviousHotKey() throws {
    let registrar = HotKeyRegistrarSpy()
    let controller = GlobalShortcutController(registrar: registrar)
    try controller.register(.optionSpace)
    try controller.register(.commandOptionSpace)
    #expect(registrar.unregisteredIDs == [1])
}
```

- [ ] **Step 2: Run AppSupport tests and confirm failure**

Run: `swift test --package-path MyMacSearch --filter GlobalShortcutControllerTests`

Expected: FAIL because controllers are missing.

- [ ] **Step 3: Implement Carbon hot-key ownership and Quick Look stale-selection protection**

Use Option-Space as the default. Registration conflict is a settings error, not an app startup failure. Window activation targets the existing MyMacSearch window and focuses/selects the search field.

- [ ] **Step 4: Implement the utility UI and AppKit table bridge**

Create a large search field, left scope/kind/date sidebar, bounded Name/Path/Kind/Size/Modified table, and bottom status bar. Implement Up/Down, Return, Space, Command-C, Escape, context menu actions, relevance/column sort, load-more, and no-scan-before-onboarding confirmation.

- [ ] **Step 5: Add source-architecture tests for required controls, commands, labels, and absence of content-search/menu-bar code**

Run: `swift test --package-path MyMacSearch`

Expected: PASS.

- [ ] **Step 6: Build, launch the development app, visually inspect density and keyboard focus, then review and commit**

Run: `swift build --package-path MyMacSearch -Xswiftc -warnings-as-errors`

Commit: `feat: add MyMacSearch native interface`

---

### Task 8: Performance Fixtures and One-million-entry Benchmark

**Files:**
- Create: `MyMacSearch/Tests/MyMacSearchCoreTests/LargeIndexRegressionTests.swift`
- Create: `MyMacSearch/Tests/MyMacSearchCoreTests/IndexPerformanceTests.swift`
- Create: `MyMacSearch/scripts/run-performance-benchmark.sh`

**Interfaces:**
- Consumes: writer and reader APIs.
- Produces: deterministic 100,000-entry regular fixture and opt-in 1,000,000-entry release benchmark report.

- [ ] **Step 1: Write the 100,000-entry correctness test and opt-in benchmark harness**

```swift
@Test func millionEntryBenchmark() async throws {
    guard ProcessInfo.processInfo.environment["MYMACSEARCH_RUN_MILLION_BENCHMARK"] == "1" else { return }
    let metrics = try await BenchmarkFixture(entryCount: 1_000_000).runRepresentativeQueries()
    #expect(metrics.warmP95Milliseconds <= 100)
}
```

- [ ] **Step 2: Run regular large-index tests and diagnose any correctness or memory failure before optimizing**

Run: `swift test --package-path MyMacSearch --filter LargeIndexRegressionTests`

Expected: PASS with exact result sets for text and filters.

- [ ] **Step 3: Run the release-mode million benchmark and record p50, p95, database size, hardware, and query set**

Run: `MyMacSearch/scripts/run-performance-benchmark.sh`

Expected: exit 0 and warmed ordinary selective query p95 at or below 100 ms.

- [ ] **Step 4: If the target is missed, capture query plans and optimize only proven bottlenecks**

Use `EXPLAIN QUERY PLAN`, transaction timings, and database size evidence. Preserve result correctness tests through any index change.

- [ ] **Step 5: Run full tests, review benchmark artifacts are outside Git, and commit**

Commit: `test: add MyMacSearch scale benchmarks`

---

### Task 9: Bundle, Personal ZIP, Install Simulation, and Documentation

**Files:**
- Create: `MyMacSearch/Sources/MyMacSearchApp/Resources/MyMacSearchInfo.plist`
- Create: `MyMacSearch/Sources/MyMacSearchApp/Resources/AppIcon.icns`
- Create: `MyMacSearch/scripts/build-app-bundle.sh`
- Create: `MyMacSearch/scripts/package-personal.sh`
- Create: `MyMacSearch/scripts/check-distribution.sh`
- Create: `MyMacSearch/Tests/MyMacSearchAppSupportTests/ReleasePackagingTests.swift`
- Create: `MyMacSearch/README.md`
- Modify: `README.md`
- Create: `MyMacSearch/docs/qa/2026-08-14-release-verification.md`

**Interfaces:**
- Produces: `MyMacSearch/build/MyMacSearch.app`.
- Produces: `MyMacSearch/dist/MyMacSearch-personal-mac.zip`.
- Produces: installer variables `MYMACSEARCH_INSTALL_DIR` and `MYMACSEARCH_SKIP_OPEN` for isolated verification.

- [ ] **Step 1: Write failing source-level packaging tests**

```swift
@Test func installerUsesRollbackAndVerifiesBeforePublishing() throws {
    let script = try fixture("scripts/package-personal.sh")
    #expect(script.contains(".MyMacSearch.installing"))
    #expect(script.contains("codesign --verify --deep --strict"))
    #expect(script.contains("MYMACSEARCH_INSTALL_DIR"))
}
```

- [ ] **Step 2: Run packaging tests and confirm missing-resource/script failure**

Run: `swift test --package-path MyMacSearch --filter ReleasePackagingTests`

Expected: FAIL until resources and scripts exist.

- [ ] **Step 3: Implement explicit bundle construction and personal ZIP scripts**

Use bundle ID `com.biglol.MyMacSearch`, executable `MyMacSearchApp`, app name `MyMacSearch`, version `0.1.0`, build `1`, Utilities category, and minimum OS `14.0`. Ad-hoc sign and strictly verify the bundle. The installer uses unique staging/backup paths, restores on failure, and never removes Application Support data or empties Trash.

- [ ] **Step 4: Implement distribution simulation and run it**

Run:

```bash
MyMacSearch/scripts/package-personal.sh
MyMacSearch/scripts/check-distribution.sh MyMacSearch/dist/MyMacSearch-personal-mac.zip
/usr/bin/unzip -tq MyMacSearch/dist/MyMacSearch-personal-mac.zip
codesign --verify --deep --strict --verbose=2 MyMacSearch/build/MyMacSearch.app
```

Expected: PASS; temporary installed executable hash equals packaged hash.

- [ ] **Step 5: Update app/root README and QA record with exact behavior, permissions, filters, exclusions, limitations, commands, test counts, hashes, and evidence boundaries**

Do not add the root download link until the final artifact has passed every verification gate.

- [ ] **Step 6: Run both full suites, warning-strict builds, diff checks, and changed-file review**

Run:

```bash
swift test --package-path MyMacSearch
swift build --package-path MyMacSearch -Xswiftc -warnings-as-errors
swift test --package-path MyMacFinder
swift build --package-path MyMacFinder -Xswiftc -warnings-as-errors
git diff --check
git status --short
```

Expected: PASS with only intended source, docs, scripts, resources, and approved artifacts changed.

- [ ] **Step 7: Commit verified source and documentation before binary artifact commit**

Commit: `docs: add MyMacSearch usage and packaging`

---

### Task 10: Release Artifact, Safe Installation, and Final Verification

**Files:**
- Update: `downloads/MyMacFinder/MyMacFinder-personal-mac.zip`
- Create: `downloads/MyMacSearch/MyMacSearch-personal-mac.zip`
- Update: `MyMacSearch/docs/qa/2026-08-14-release-verification.md`

**Interfaces:**
- Consumes: verified app bundles and ZIPs from Task 9.
- Produces: `/Applications/MyMacSearch.app`, a compatible `/Applications/MyMacFinder.app`, final hashes, and exact running process evidence.

- [ ] **Step 1: Regenerate MyMacFinder and MyMacSearch packages from reviewed HEAD and verify ZIP integrity/signatures**

Run:

```bash
MyMacFinder/scripts/package_personal.sh
MyMacSearch/scripts/package-personal.sh
/usr/bin/unzip -tq MyMacFinder/dist/MyMacFinder-personal-mac.zip
/usr/bin/unzip -tq MyMacSearch/dist/MyMacSearch-personal-mac.zip
codesign --verify --deep --strict MyMacFinder/build/MyMacFinder.app
codesign --verify --deep --strict MyMacSearch/build/MyMacSearch.app
```

- [ ] **Step 2: Copy only the final ZIPs to downloads and verify copied hashes**

Use `ditto` or `cp` after creating destination directories. Compare SHA-256 for source and destination before continuing.

- [ ] **Step 3: Install through unique `/Applications` staging and rollback paths**

Stop only processes whose exact executable paths match the two installed apps. Verify staged signature/hash before the same-volume rename. Preserve replaced bundles as recoverable Trash backups until new launches pass.

- [ ] **Step 4: Verify installed plist, signature, executable hashes, exact process paths, and immediate-crash checks**

Run `plutil`, `codesign --verify --deep --strict --verbose=2`, `shasum -a 256`, and exact `ps` path checks. Confirm build/package/staged/installed executable hashes match per app.

- [ ] **Step 5: Perform manual release QA**

Confirm onboarding, partial scanning, query grammar, filters, Up/Down, Return, Space, Command-C, Escape, Option-Space, pause/resume, permission settings link, missing paths, Terminal, Finder, and MyMacFinder directory routing. Record anything not directly exercised as `MANUAL VERIFICATION REQUIRED` rather than claiming it passed.

- [ ] **Step 6: Re-run final automated gates and inspect every changed file**

Run full tests, warning-strict builds, ZIP checks, strict signatures, `git diff --check`, `git status --short`, artifact hashes, and changed-file listing. Verify `.build`, temporary `dist`, staging apps, and QA fixtures are untracked/ignored and absent from commits.

- [ ] **Step 7: Commit artifacts and final evidence**

Commit: `release: add MyMacSearch personal build`

## Plan Self-Review

- Spec coverage: Tasks cover the three-target package, runtime FTS failure, metadata-only index, cancellation, permission skips, scan/watch handoff, FSEvents recovery, parser grammar, performance, native UI, global shortcut, Quick Look, all requested actions, MyMacFinder compatibility, packaging, downloads, installation, README, and verification.
- Scope: Content/OCR/PDF body, Spotlight-primary, fuzzy search, menu bar, helper process, public notarization, and file mutation remain excluded.
- Type consistency: Task 1 owns shared query/domain values; Task 2 owns writer/reader database actors; Task 3 emits writer batches; Task 4 coordinates scanner/watcher/writer; Task 5 reads through the reader; Tasks 6 and 7 consume AppSupport state without bypassing those boundaries.
- Safety: Old scan generations are pruned only after completion; FSEvents cannot bridge scans without buffering; stale async completions are generation-guarded; external actions revalidate paths; installers use verified staging and recoverable rollback.
