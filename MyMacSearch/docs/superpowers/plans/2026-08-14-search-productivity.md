# MyMacSearch Search Productivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic result sorting, size filters, recent and saved searches, removable filter tokens, and safe multi-selection while retaining one-million-entry responsiveness.

**Architecture:** Replace the query-only search boundary with a `SearchRequest` containing parsed metadata filters and a stable sort. SQLite continues to use bound parameters and keyset pagination. Small user workflow data is kept in an atomic JSON search library, independent of index settings and SQLite.

**Tech Stack:** Swift 6, SwiftUI Table, Observation, SQLite3/FTS5, QuickLookUI, XCTest, macOS 14+.

## Global Constraints

- Complete `2026-08-14-index-health-foundation.md` first because this plan relies on schema version 2 and per-scope availability.
- Keep the 60 ms search debounce and a 200-row default result window.
- Do not use `OFFSET` pagination.
- Do not add file-content search, OCR, PDF body search, fuzzy search, wildcards, negative filters, or regular expressions.
- Batch Open is excluded; Enter opens only the primary selection.
- Do not commit `.build`, `build`, `dist`, or temporary benchmark databases.

---

### Task 1: Search request, sort modes, and sort-specific cursors

**Files:**
- Create: `Sources/MyMacSearchCore/Models/SearchRequest.swift`
- Modify: `Sources/MyMacSearchCore/Models/IndexModels.swift`
- Modify: `Sources/MyMacSearchCore/Index/IndexSearching.swift`
- Modify: `Sources/MyMacSearchCore/Index/SQLiteIndexReader.swift`
- Modify: `Tests/MyMacSearchCoreTests/SQLiteSearchTests.swift`
- Modify: `Tests/MyMacSearchAppSupportTests/SearchViewModelTests.swift`

**Interfaces:**
- Consumes: `SearchQuery`, existing relevance ranking, and the version 2 sort indexes.
- Produces: `SearchSort`, `SearchRequest`, `SearchPageCursor`, and a request-based `IndexSearching` protocol.

- [ ] **Step 1: Write failing deterministic sort tests**

```swift
func testNameSortUsesEntryIDAsFinalTieBreakerAcrossPages() async throws {
    let fixture = try TemporaryIndexFixture(entries: [
        .testEntry(id: 3, path: "/z/Report.swift", modifiedAt: date(300)),
        .testEntry(id: 1, path: "/a/report.swift", modifiedAt: date(100)),
        .testEntry(id: 2, path: "/b/REPORT.swift", modifiedAt: date(200))
    ])
    defer { fixture.remove() }

    let request = SearchRequest(query: SearchQuery(), sort: .nameAscending)
    let first = try await fixture.reader.search(request: request, limit: 2, after: nil)
    let second = try await fixture.reader.search(
        request: request, limit: 2, after: first.nextCursor
    )

    XCTAssertEqual((first.entries + second.entries).map(\.id), [1, 2, 3])
}
```

Add literal expected-order tests for relevance, both name orders, both path orders, both modified orders, both size orders, and kind-then-name. Include equal sort values and a row inserted between pages.

- [ ] **Step 2: Run the sort test and confirm RED**

Run: `swift test --filter SQLiteSearchTests.testNameSortUsesEntryIDAsFinalTieBreakerAcrossPages`

Expected: compile failure because `SearchRequest` and `.nameAscending` do not exist.

- [ ] **Step 3: Add request and cursor models**

```swift
public enum SearchSort: String, CaseIterable, Codable, Sendable {
    case relevance, nameAscending, nameDescending
    case pathAscending, pathDescending
    case modifiedNewest, modifiedOldest
    case sizeLargest, sizeSmallest
    case kindThenName
}

public struct SearchRequest: Equatable, Sendable {
    public var query: SearchQuery
    public var sort: SearchSort
}

public enum SearchPageCursor: Codable, Equatable, Sendable {
    case relevance(rank: Double, modifiedAt: Date, entryID: Int64)
    case text(value: String, entryID: Int64)
    case date(value: Date, entryID: Int64)
    case size(value: Int64, entryID: Int64)
    case kind(kind: String, name: String, entryID: Int64)
}
```

Replace `SearchCursor` in `SearchPage` with `SearchPageCursor`. Do not keep two cursor types.

- [ ] **Step 4: Change the search boundary**

```swift
public protocol IndexSearching: Sendable {
    func search(
        request: SearchRequest,
        limit: Int,
        after cursor: SearchPageCursor?
    ) async throws -> SearchPage
}
```

Update test doubles and `SearchViewModel` temporarily to send `.relevance` for non-empty queries and `.modifiedNewest` for empty queries. Keep all existing race and paging tests compiling before adding user-selected sort.

- [ ] **Step 5: Implement sort SQL and cursor predicates**

Create one internal `SearchOrder` value per `SearchSort` containing the SQL order clause, cursor predicate, cursor bindings, and cursor extraction. Bind every cursor value; never interpolate user data. Every order ends with `id ASC` or `id DESC` matching its cursor predicate.

Examples:

```sql
ORDER BY search_name ASC, id ASC
```

```sql
WHERE search_name > ? OR (search_name = ? AND id > ?)
```

Relevance retains rank ascending, modified descending, ID ascending. Path uses normalized `search_path`; kind uses kind ascending, normalized name ascending, ID ascending.

- [ ] **Step 6: Run core and view-model tests**

Run: `swift test --filter SQLiteSearchTests && swift test --filter SearchViewModelTests`

Expected: all sort, cursor, stale-query, and Load More tests pass without duplicates.

- [ ] **Step 7: Commit the request boundary**

```bash
git add MyMacSearch/Sources/MyMacSearchCore MyMacSearch/Sources/MyMacSearchAppSupport/SearchViewModel.swift \
  MyMacSearch/Tests/MyMacSearchCoreTests/SQLiteSearchTests.swift \
  MyMacSearch/Tests/MyMacSearchAppSupportTests/SearchViewModelTests.swift
git commit -m "feat: add sortable MyMacSearch requests"
```

### Task 2: Size filter and removable token metadata

**Files:**
- Modify: `Sources/MyMacSearchCore/Models/SearchQuery.swift`
- Create: `Sources/MyMacSearchCore/Models/SearchQueryToken.swift`
- Modify: `Sources/MyMacSearchCore/Search/SearchQueryParser.swift`
- Modify: `Sources/MyMacSearchCore/Index/SQLiteIndexReader.swift`
- Modify: `Tests/MyMacSearchCoreTests/SearchQueryParserTests.swift`
- Modify: `Tests/MyMacSearchCoreTests/SQLiteSearchTests.swift`

**Interfaces:**
- Consumes: canonical query text.
- Produces: `ByteSizeRange`, `ParsedSearchQuery`, character-offset tokens, and bound size predicates.

- [ ] **Step 1: Write table-driven failing size tests**

```swift
func testParsesSupportedSizeFilters() throws {
    let cases: [(String, ByteSizeRange)] = [
        ("size:>100MB", .greaterThan(104_857_600)),
        ("size:>=1GB", .atLeast(1_073_741_824)),
        ("size:<500KB", .lessThan(512_000)),
        ("size:10MB..1GB", .closed(10_485_760, 1_073_741_824))
    ]
    for (input, expected) in cases {
        XCTAssertEqual(try SearchQueryParser.parse(input).sizeRange, expected)
    }
}
```

Add failures for missing units, unsupported units, negative values, overflow, empty bounds, and reversed ranges. Add a token test proving removal offsets isolate `kind:pdf` in `report kind:pdf path:"Project Files"` without changing the other text.

- [ ] **Step 2: Run parser tests and confirm RED**

Run: `swift test --filter SearchQueryParserTests`

Expected: unknown-filter failure for `size:` and missing token metadata.

- [ ] **Step 3: Add size and token models**

```swift
public enum ByteSizeRange: Equatable, Sendable {
    case greaterThan(Int64)
    case atLeast(Int64)
    case lessThan(Int64)
    case atMost(Int64)
    case closed(Int64, Int64)
}

public struct SearchQueryToken: Equatable, Sendable {
    public let filter: String
    public let rawText: String
    public let characterRange: Range<Int>
}

public struct ParsedSearchQuery: Equatable, Sendable {
    public let query: SearchQuery
    public let tokens: [SearchQueryToken]
}
```

Add `sizeRange` to `SearchQuery`. Preserve `SearchQueryParser.parse(_:) -> SearchQuery` as a convenience wrapper over `parseDetailed(_:)` so callers migrate incrementally.

- [ ] **Step 4: Implement strict byte parsing**

Normalize units case-insensitively, multiply using `multipliedReportingOverflow`, and reject decimals in V1.1. Character ranges count Swift `Character` values from the original input, including quotes, so the UI can derive valid `String.Index` boundaries safely.

- [ ] **Step 5: Add bound SQLite predicates**

Map every range case to `size_bytes` predicates with `.int64` bindings. Do not inject numeric text into SQL. Add literal result fixtures for files below, inside, and above each boundary.

- [ ] **Step 6: Run parser and SQLite tests**

Run: `swift test --filter SearchQueryParserTests && swift test --filter SQLiteSearchTests`

Expected: all legacy and size-filter tests pass.

- [ ] **Step 7: Commit metadata filters**

```bash
git add MyMacSearch/Sources/MyMacSearchCore MyMacSearch/Tests/MyMacSearchCoreTests
git commit -m "feat: add MyMacSearch size filters and tokens"
```

### Task 3: Atomic recent and saved search library

**Files:**
- Create: `Sources/MyMacSearchAppSupport/SearchLibrary.swift`
- Create: `Sources/MyMacSearchAppSupport/SearchLibraryStore.swift`
- Create: `Tests/MyMacSearchAppSupportTests/SearchLibraryStoreTests.swift`

**Interfaces:**
- Consumes: successful query text and `SearchSort`.
- Produces: a versioned `SearchLibrary.json` with last-good recovery, 20 bounded recent searches, and ordered saved searches.

- [ ] **Step 1: Write failing persistence tests**

```swift
func testRecentSearchesAreBoundedAndDeduplicated() throws {
    let fixture = try SearchLibraryFixture()
    for index in 0..<25 {
        try fixture.store.recordRecent(
            query: "query-\(index)", sort: .nameAscending,
            usedAt: Date(timeIntervalSince1970: Double(index))
        )
    }
    try fixture.store.recordRecent(
        query: "query-20", sort: .sizeLargest,
        usedAt: Date(timeIntervalSince1970: 100)
    )

    let library = try fixture.store.load()
    XCTAssertEqual(library.recent.count, 20)
    XCTAssertEqual(library.recent.first?.query, "query-20")
    XCTAssertEqual(library.recent.first?.sort, .sizeLargest)
    XCTAssertEqual(library.recent.filter { $0.query == "query-20" }.count, 1)
}
```

Add tests for corrupt-primary recovery, corrupt-both failure, save/rename/replace/remove/reorder, duplicate display names with unique IDs, and ignoring empty queries.

- [ ] **Step 2: Run store tests and confirm RED**

Run: `swift test --filter SearchLibraryStoreTests`

Expected: compile failure because the library and store do not exist.

- [ ] **Step 3: Add versioned library models**

```swift
public struct RecentSearch: Codable, Equatable, Identifiable, Sendable {
    public var id: String { query }
    public let query: String
    public let sort: SearchSort
    public let lastUsedAt: Date
}

public struct SavedSearch: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var query: String
    public var sort: SearchSort
    public let createdAt: Date
    public var lastUsedAt: Date
}

public struct SearchLibrary: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var recent: [RecentSearch] = []
    public var saved: [SavedSearch] = []
}
```

Normalize queries for deduplication by trimming leading/trailing whitespace and collapsing runs of unquoted whitespace without altering quoted text.

- [ ] **Step 4: Implement atomic primary and last-good writes**

Mirror `SearchSettingsStore`: validate encoded data by decoding it, copy a valid previous primary to `SearchLibrary.last-good.json`, write atomically, and recover from last-good on load. Clamp recent searches to 20 after every mutation.

- [ ] **Step 5: Run library tests**

Run: `swift test --filter SearchLibraryStoreTests`

Expected: all persistence and recovery tests pass.

- [ ] **Step 6: Commit the library**

```bash
git add MyMacSearch/Sources/MyMacSearchAppSupport/SearchLibrary.swift \
  MyMacSearch/Sources/MyMacSearchAppSupport/SearchLibraryStore.swift \
  MyMacSearch/Tests/MyMacSearchAppSupportTests/SearchLibraryStoreTests.swift
git commit -m "feat: persist MyMacSearch search library"
```

### Task 4: Search view-model workflow

**Files:**
- Modify: `Sources/MyMacSearchAppSupport/SearchViewModel.swift`
- Create: `Tests/MyMacSearchAppSupportTests/SearchWorkflowTests.swift`
- Modify: `Tests/MyMacSearchAppSupportTests/SearchViewModelTests.swift`

**Interfaces:**
- Consumes: `IndexSearching`, detailed parser output, and `SearchLibraryStore`.
- Produces: active sort, tokens, recent/saved actions, and stale-safe persistence after successful searches.

- [ ] **Step 1: Write failing workflow tests**

```swift
@MainActor
func testOnlySuccessfulCurrentSearchIsRecordedAsRecent() async throws {
    let searcher = ControlledSearcher()
    let library = RecordingSearchLibraryStore()
    let model = SearchViewModel(searcher: searcher, libraryStore: library, debounce: .zero)

    model.query = "old"
    model.query = "current"
    await searcher.finish(query: "current", entries: [.fixture(name: "current.txt")])
    await searcher.finish(query: "old", entries: [.fixture(name: "old.txt")])

    XCTAssertEqual(library.recordedQueries, ["current"])
}
```

Add tests for restoring saved query and sort, changing sort without losing query, token removal preserving quoted text, invalid queries not entering recent history, and saving only valid queries.

- [ ] **Step 2: Run workflow tests and confirm RED**

Run: `swift test --filter SearchWorkflowTests`

Expected: compile failure for missing sort, tokens, and library actions.

- [ ] **Step 3: Add observable workflow state**

```swift
public var sort: SearchSort { didSet { scheduleSearch() } }
public private(set) var tokens: [SearchQueryToken] = []
public private(set) var recentSearches: [RecentSearch] = []
public private(set) var savedSearches: [SavedSearch] = []
public private(set) var primaryEntryID: Int64?
public var selectedEntryIDs: Set<Int64> = []
```

Default sort is `.modifiedNewest` for an empty initial query and `.relevance` for the first non-empty query only if the user has never explicitly chosen a sort. Persist explicit sort choice in `SearchSettings`.

- [ ] **Step 4: Integrate detailed parsing and recent recording**

Set tokens only after parse success. Record recent history only after the current generation's first page succeeds. Library write failures set a separate non-blocking `libraryError` and do not discard search results.

- [ ] **Step 5: Add saved-search and token actions**

Implement `saveCurrentSearch(name:)`, `renameSavedSearch`, `replaceSavedSearch`, `removeSavedSearch`, `moveSavedSearch`, `activateSavedSearch`, `activateRecentSearch`, `clearRecentSearches`, and `removeToken(id:)`. Validate names after trimming and require non-empty valid queries for saving.

- [ ] **Step 6: Run all search view-model tests**

Run: `swift test --filter SearchViewModelTests && swift test --filter SearchWorkflowTests`

Expected: all paging, race, parser-error, library, token, and sort tests pass.

- [ ] **Step 7: Commit workflow integration**

```bash
git add MyMacSearch/Sources/MyMacSearchAppSupport/SearchViewModel.swift \
  MyMacSearch/Tests/MyMacSearchAppSupportTests/SearchViewModelTests.swift \
  MyMacSearch/Tests/MyMacSearchAppSupportTests/SearchWorkflowTests.swift
git commit -m "feat: add MyMacSearch search workflows"
```

### Task 5: Saved, recent, filters, and sortable table UI

**Files:**
- Modify: `Sources/MyMacSearchApp/Views/SearchRootView.swift`
- Modify: `Sources/MyMacSearchApp/Views/SearchResultsTable.swift`
- Create: `Sources/MyMacSearchApp/Views/SearchFilterTokensView.swift`
- Create: `Sources/MyMacSearchApp/Views/SaveSearchSheet.swift`
- Modify: `Sources/MyMacSearchApp/MyMacSearchApp.swift`
- Modify: `Tests/MyMacSearchAppSupportTests/NativeInterfaceSourceTests.swift`

**Interfaces:**
- Consumes: search workflow state and actions.
- Produces: sidebar Saved/Recent sections, token removal, save UI, sort controls, and column sort indicators.

- [ ] **Step 1: Add failing interface contract tests**

```swift
func testProductivityInterfaceKeepsSearchFirstAndAddsWorkflowControls() throws {
    let root = try source("Views/SearchRootView.swift")
    let table = try source("Views/SearchResultsTable.swift")
    XCTAssertTrue(root.contains("Search files and folders"))
    XCTAssertTrue(root.contains("Saved Searches"))
    XCTAssertTrue(root.contains("Recent"))
    XCTAssertTrue(root.contains("SearchFilterTokensView"))
    XCTAssertTrue(table.contains("SearchSort"))
    XCTAssertTrue(try allAppSource().contains("Save Search"))
}
```

- [ ] **Step 2: Run the interface test and confirm RED**

Run: `swift test --filter NativeInterfaceSourceTests.testProductivityInterfaceKeepsSearchFirstAndAddsWorkflowControls`

Expected: failure because workflow controls are absent.

- [ ] **Step 3: Add sidebar library sections**

Place Saved Searches first and Recent beneath it, both collapsible. Saved rows show the name and query in help text. Context menus provide Rename, Update with Current Search, and Remove. Recent provides Use, Save, and Clear Recent Searches. Empty sections show no placeholder cards.

- [ ] **Step 4: Add filter tokens and save sheet**

Render structured filters as compact native controls below the search field. Each token has a remove button and an accessibility label containing the full raw token. The Save Search sheet contains only name, query preview, sort preview, Cancel, and Save.

- [ ] **Step 5: Add sort controls**

Column headers set their corresponding ascending sort and toggle direction on repeated activation. Add a compact sort menu for Relevance and Kind. Display one native sort indicator. Do not reorder rows locally; every sort change issues a new SQLite request.

- [ ] **Step 6: Add keyboard commands**

Add Command-S for Save Search when the current query is valid and non-empty. Preserve Command-F, Escape, Enter, Space, and Command-C. Disabled commands must describe why in accessibility help where SwiftUI supports it.

- [ ] **Step 7: Build and run interface tests**

Run:

```bash
swift test --filter NativeInterfaceSourceTests
swift build -Xswiftc -warnings-as-errors
```

Expected: tests pass, search remains the first focus, and the app builds without warnings.

- [ ] **Step 8: Commit productivity UI**

```bash
git add MyMacSearch/Sources/MyMacSearchApp MyMacSearch/Tests/MyMacSearchAppSupportTests/NativeInterfaceSourceTests.swift
git commit -m "feat: add MyMacSearch saved search interface"
```

### Task 6: Safe multi-selection and multi-file Quick Look

**Files:**
- Modify: `Sources/MyMacSearchAppSupport/ResultActionService.swift`
- Modify: `Sources/MyMacSearchAppSupport/QuickLookPreviewController.swift`
- Modify: `Sources/MyMacSearchApp/Views/SearchResultsTable.swift`
- Modify: `Sources/MyMacSearchApp/AppModel.swift`
- Modify: `Tests/MyMacSearchAppSupportTests/ResultActionServiceTests.swift`
- Modify: `Tests/MyMacSearchAppSupportTests/QuickLookPreviewControllerTests.swift`
- Modify: `Tests/MyMacSearchAppSupportTests/SearchWorkflowTests.swift`

**Interfaces:**
- Consumes: selected entry IDs and current visible row order.
- Produces: deterministic primary selection, multi-path copy/reveal, and navigable Quick Look.

- [ ] **Step 1: Write failing multi-selection tests**

```swift
@MainActor
func testCopyPathsUsesVisibleOrderAndNewlineSeparation() async throws {
    let environment = ResultActionEnvironmentSpy(status: .file)
    let service = ResultActionService(environment: environment)
    try await service.copyPaths([
        .actionFixture(path: "/a/one.txt"),
        .actionFixture(path: "/b/two.txt")
    ])
    XCTAssertEqual(environment.copiedText, "/a/one.txt\n/b/two.txt")
}
```

Add tests that Reveal caps input at 100, missing paths are reconciled and consolidated, Enter resolves the newest added selection as primary, fallback primary uses visible order, and Quick Look returns all valid URLs in visible order.

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `swift test --filter ResultActionServiceTests && swift test --filter QuickLookPreviewControllerTests && swift test --filter SearchWorkflowTests`

Expected: compile failure for multi-entry APIs.

- [ ] **Step 3: Extend action environment safely**

```swift
@MainActor
public protocol ResultActionEnvironment: AnyObject {
    func reveal(_ urls: [URL]) -> Bool
    func copyText(_ text: String) -> Bool
}
```

Keep single Open, Terminal, and MyMacFinder actions. Add `copyPaths(_:)` and `revealInFinder(_:)`. Resolve statuses first, call `onMissingPath` for missing entries, then perform one pasteboard or Finder request for valid entries. Return a structured partial-failure error containing missing and unavailable counts.

- [ ] **Step 4: Make Quick Look list-based**

Replace `previewURL` with `previewURLs: [URL]` and `selectedPreviewIndex`. `numberOfPreviewItems` returns the list count; `previewItemAt` bounds-checks the index. Preserve generation-guarded stale clears.

- [ ] **Step 5: Wire deterministic selection**

Bind the table to `selectedEntryIDs`. `SearchViewModel.updateSelection(_:)` compares old and new sets, chooses a newly added row as primary using current visible row order, and falls back to the earliest visible selected row after removals or refresh. Search refresh retains only selected IDs present in the new first page.

- [ ] **Step 6: Preserve keyboard safety**

Command-C copies all selected paths. Space previews all selected valid entries. Enter opens only `primaryEntryID`. Context menus label plural actions when multiple rows are selected. Do not add batch Open.

- [ ] **Step 7: Run action, Quick Look, keyboard, and workflow tests**

Run:

```bash
swift test --filter ResultActionServiceTests
swift test --filter QuickLookPreviewControllerTests
swift test --filter ResultKeyboardCommandTests
swift test --filter SearchWorkflowTests
```

Expected: all tests pass, including stale Quick Look generation behavior.

- [ ] **Step 8: Commit multi-selection**

```bash
git add MyMacSearch/Sources/MyMacSearchAppSupport MyMacSearch/Sources/MyMacSearchApp \
  MyMacSearch/Tests/MyMacSearchAppSupportTests
git commit -m "feat: add safe MyMacSearch multi-selection"
```

### Task 7: Performance, live QA, documentation, and package

**Files:**
- Modify: `Tests/MyMacSearchCoreTests/LargeIndexRegressionTests.swift`
- Modify: `Tests/MyMacSearchCoreTests/IndexPerformanceTests.swift`
- Modify: `README.md`
- Create: `docs/qa/2026-08-14-search-productivity-verification.md`
- Modify: `../downloads/MyMacSearch/MyMacSearch-personal-mac.zip`

**Interfaces:**
- Consumes: the completed V1.1B productivity implementation.
- Produces: deterministic scale evidence, live keyboard/UI evidence, and a verified personal installer.

- [ ] **Step 1: Extend scale regressions**

For 100,000 rows, assert the exact first and second page for every sort and size-filter boundary. For the opt-in one-million benchmark, record warm p50 and p95 for each supported sort using a 200-row page and fail if selective-query p95 exceeds 50 ms.

- [ ] **Step 2: Run full automated verification**

```bash
swift test
MYMACSEARCH_RUN_MILLION_BENCHMARK=1 swift test -c release --filter IndexPerformanceTests
swift build -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
```

- [ ] **Step 3: Run isolated live UI QA**

Verify search-field focus, every sort direction, Load More boundaries, recent deduplication, save/rename/update/remove/reorder, token removal with quoted values, valid and invalid size filters, multi-select Copy Paths, Finder reveal cap, multi-file Quick Look navigation, Enter opening only the primary row, offline badges, and simultaneous Index Center refresh.

- [ ] **Step 4: Package and verify installation**

```bash
MyMacSearch/scripts/package-personal.sh
MyMacSearch/scripts/check-distribution.sh
codesign --verify --deep --strict --verbose=2 /Applications/MyMacSearch.app
git diff --check
```

Compare packaged and installed executable hashes and confirm `.build`, benchmark databases, and temporary distributions are absent from the commit.

- [ ] **Step 5: Commit release evidence**

```bash
git add MyMacSearch/README.md MyMacSearch/docs/qa \
  downloads/MyMacSearch/MyMacSearch-personal-mac.zip
git commit -m "release: verify MyMacSearch search productivity"
```
