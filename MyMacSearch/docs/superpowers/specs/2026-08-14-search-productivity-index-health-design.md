# MyMacSearch Search Productivity and Index Health Design

**Date:** 2026-08-14
**Status:** Approved
**Target:** MyMacSearch V1.1–V1.2

## Summary

MyMacSearch will evolve from a fast metadata search MVP into a quiet, keyboard-first search workbench. The next release combines two mutually reinforcing areas:

1. Search productivity: sortable results, recent and saved searches, removable filter tokens, stronger metadata filters, and safe multi-selection.
2. Index trust: per-location state, durable issue history, volume availability, manual reconciliation, and explicit index verification and repair.

The design keeps the current initial scan + SQLite FTS5 + FSEvents architecture. It does not add file-content search, OCR, PDF body search, Spotlight dependence, fuzzy matching, regular expressions, or file mutation.

## Product Principles

- The main window remains the tool. It must open directly to the search field and results.
- Search must remain responsive at one million indexed entries.
- Reliability information must be visible without turning the app into a monitoring dashboard.
- A cancelled or failed rescan must not remove the last complete entries for a scope.
- Offline external or network scopes retain their cached entries and are marked unavailable; they are not silently purged.
- Maintenance changes only MyMacSearch-owned index files. It never modifies or deletes indexed user files.
- New persistent files use atomic writes and last-good recovery.

## Considered Approaches

### Balanced Search Workbench — selected

Deliver index observability first, then layer saved searches, sort modes, filter tokens, and multi-selection onto those stable foundations. This produces visible daily value while keeping failures diagnosable.

### Power-user syntax first

Prioritize wildcards, negative expressions, regular expressions, and extensive query grammar. This is powerful but increases parser, SQL, pagination, and discoverability complexity before the app exposes enough index health information.

### Operations center first

Build comprehensive index diagnostics and repair before search workflow improvements. This maximizes operational confidence but offers little immediate improvement to everyday searching.

## Information Architecture

The current three-part layout remains:

- Sidebar: saved searches, recent searches, indexed locations, kind filters, date filters, and size filters.
- Main area: large search field, active filter tokens, results table, and compact result controls.
- Status bar: live indexing state, result window count, issue indicator, and a button that opens Index Center.

Index Center is a focused sheet or secondary window, not a new home screen. It has three sections:

- Overview: total indexed entries, database size, last verification, and overall state.
- Locations: one row per scope with availability, indexed count, last completed scan, last event, issue counts, and Rescan.
- Issues and Maintenance: bounded issue history, Verify Index, Rebuild Search Index, and Rebuild Entire Index.

## Search Productivity Features

### Sortable, stable results

Supported sort modes:

- Relevance, then newest modified date. This remains the default for non-empty text queries.
- Name ascending and descending.
- Path ascending and descending.
- Modified newest and oldest.
- Size largest and smallest.
- Kind, then name.

All modes use keyset pagination. `OFFSET` pagination is prohibited because it degrades and can duplicate or skip rows while the index changes. Every sort order ends with entry ID as a deterministic tie-breaker.

When the query is empty, Modified Newest is the default. The selected sort persists across launches, but a user-selected mode is never silently replaced when the query changes.

### Recent searches

- Keep at most 20 unique successful queries.
- Ignore empty, invalid, and failed queries.
- Move a repeated query to the top rather than duplicating it.
- Record a query after its first page succeeds and it remains current.
- Provide Clear Recent Searches in the sidebar context menu.
- Store only the query text and last-used date; do not retain result paths.

### Saved searches

- A saved search contains an ID, user-visible name, query text, sort mode, creation date, and last-used date.
- Users can save the current valid query, rename it, replace its definition, remove it, and reorder saved searches.
- Selecting a saved search restores the query and sort mode, focuses the result table, and executes immediately.
- Duplicate names are allowed, but IDs are unique.
- Recent and saved searches live in `SearchLibrary.json`, separate from indexing policy settings.

### Active filter tokens

Structured filters are shown as removable tokens below the search field while the editable query remains canonical text. Removing a token rewrites only that parsed token and preserves free text and quoted values.

The first token set includes:

- `ext:`
- `kind:`
- `path:`
- `name:`
- `modified:`
- `size:`

The sidebar continues to insert valid textual filters. The token row is hidden when no structured filters exist.

### Size filter

Add these forms:

- `size:>100MB`
- `size:>=1GB`
- `size:<500KB`
- `size:10MB..1GB`

Units are case-insensitive and limited to B, KB, MB, GB, and TB using powers of 1024. Negative values, reversed ranges, missing units, and overflow are parse errors. Directories do not match positive size filters unless their indexed size satisfies the predicate.

Negative filters, wildcard syntax, and regular expressions remain deferred.

### Safe multi-selection

The result table selection becomes a set of entry IDs with one primary selection.

- Command-C copies every selected path separated by newlines.
- Reveal in Finder reveals up to 100 selected URLs in one request.
- Quick Look previews the selected files as a navigable set.
- Enter opens only the primary selection.
- Batch Open is not included because accidentally opening hundreds of files is disruptive.
- Missing or offline selections produce a consolidated, non-blocking error and remain safe to remove from the index through normal reconciliation.

## Index Health Features

### Per-scope runtime state

Each configured scope exposes one of these states:

- Scanning
- Watching
- Paused
- Offline
- Permission Needed
- Error
- Disabled

The global status is derived from scope states. One offline network share does not change healthy local scopes to Error.

Each scope health record includes:

- Root path and volume type.
- Current availability.
- Indexed entry count.
- Last completed scan date.
- Last processed FSEvents event date and checkpoint.
- Current scan progress when scanning.
- Skipped and permission-denied counts.
- Unresolved issue count and last error.

### Durable issue history

Index problems are stored in SQLite rather than disappearing whenever the coordinator restarts. Records are coalesced by scope, normalized path, and category.

Categories include permission denied, unavailable root, metadata read failure, scan failure, dropped events, and database maintenance failure. A record stores first seen, last seen, occurrence count, resolved date, and a concise message.

The store retains at most 1,000 unresolved or recent records. Resolved records older than 30 days are pruned during idle maintenance. Index Center can filter by location and category and copy a path, but it does not modify the affected user file.

### External and network volume lifecycle

- Observe workspace volume mount and unmount notifications.
- Validate the root and volume identity before starting or resuming a watcher.
- On unmount, stop work for that scope, mark it Offline, and retain its index rows.
- Offline rows remain searchable with a muted availability badge.
- On remount with the expected volume identity, reconcile that scope before returning it to Watching.
- If the mount path is reused by a different volume, do not assume identity; require an explicit scope update or user action.

### Manual rescan

Index Center offers Rescan for one scope and Rescan All. Existing generation semantics remain: new rows are written under a new generation and old rows are pruned only after the scan completes. Cancellation or failure therefore preserves the last complete scope snapshot.

Only one full scan runs at a time. Additional rescan requests are coalesced per scope and shown as queued.

### Index verification

Verify Index runs off the main actor and reports:

- `PRAGMA quick_check` result.
- FTS5 integrity check result.
- Entry and FTS row consistency.
- Database, WAL, and shared-memory file sizes.
- Scope rows whose root no longer matches settings.

Verification is never run on every search or status refresh. It runs on demand and after a repair, with the last successful result cached for Index Center.

### Repair and rebuild

Rebuild Search Index recreates only FTS data from the metadata table when metadata is healthy. It is preferred over a filesystem rescan for FTS-only corruption.

Rebuild Entire Index creates a new database at `Index.rebuilding.sqlite3`, scans enabled scopes, verifies the new database, closes readers and writers, and atomically swaps it into service. The old database and WAL sidecars remain as a rollback backup until the new reader opens successfully. A failed or cancelled rebuild leaves the active index untouched.

Maintenance never runs automatically when it may require database-sized temporary disk space. The UI shows an estimated space requirement and obtains in-app confirmation before a full rebuild.

## Architecture

### Search domain

Add these focused types to `MyMacSearchCore`:

```swift
public enum SearchSort: Codable, Equatable, Sendable
public struct SearchRequest: Equatable, Sendable
public enum SearchPageCursor: Codable, Equatable, Sendable
public struct ByteSizeRange: Equatable, Sendable
```

`SearchRequest` contains the parsed `SearchQuery` and selected `SearchSort`. `IndexSearching.search` accepts a request rather than a bare query. `SearchPageCursor` carries the specific final sort values needed by each sort mode and always includes the entry ID tie-breaker.

`SearchQueryParser` returns both semantic filters and token source ranges so the UI can remove a structured filter without reconstructing unrelated text.

### Search library

Add `SavedSearch`, `RecentSearch`, and `SearchLibrary` models plus a `SearchLibraryStore`. The store writes `SearchLibrary.json` and `SearchLibrary.last-good.json` atomically using a versioned schema. `SearchViewModel` consumes the store through a protocol so query execution and persistence remain independently testable.

### Index health domain

Add these types to `MyMacSearchCore`:

```swift
public enum ScopeIndexState: Equatable, Sendable
public struct IndexScopeHealth: Equatable, Sendable
public struct IndexHealthSnapshot: Equatable, Sendable
public struct IndexIssueRecord: Identifiable, Equatable, Sendable
public protocol IndexHealthReading: Sendable
public protocol IndexMaintaining: Sendable
```

`SQLiteIndexHealthReader` reads persisted counts, timestamps, issues, and integrity state. `IndexCoordinator` owns live scope state and exposes targeted `rescan(scopeID:)` without moving SQLite diagnostic SQL into the UI layer. `IndexHealthViewModel` combines the live coordinator snapshot with persisted health data for Index Center.

### Database migration

Schema version 2 adds:

- `scopes.last_completed_scan_at`
- `scopes.last_event_at`
- `scopes.last_error`
- `index_issues`
- indexes supporting name, path, kind, size, and modified keyset orders

Migration runs in one SQLite transaction and updates `PRAGMA user_version` only after success. It does not rebuild the existing entries or FTS table. Opening a version 1 index must preserve all rows and checkpoints.

## Data Flow

### Search

1. The user edits query text or chooses a saved search.
2. The parser returns semantic filters plus token ranges.
3. `SearchViewModel` creates a `SearchRequest` with the active sort.
4. `SQLiteIndexReader` generates bound SQL and a sort-specific keyset cursor.
5. The first page replaces the visible window; Load More appends unique paths.
6. A successful current query updates recent-search storage.

### Index health

1. FSEvents, scans, mount notifications, and maintenance operations update live scope state.
2. Completed scans and handled events persist timestamps and checkpoints.
3. Failures are coalesced into `index_issues` and reflected in the affected scope.
4. Index Center requests an on-demand health snapshot; the status bar uses a lightweight cached summary only.
5. A rescan or repair updates state progressively and refreshes search results only after a consistent milestone.

## Error Handling and Safety

- Search library corruption falls back to the last-good file and surfaces a recoverable warning.
- A health-query failure does not block normal searches.
- A scope failure changes only that scope unless the SQLite database itself is unavailable.
- Permission failures remain recorded and do not crash or abort unrelated scopes.
- Offline actions identify the unavailable volume rather than reporting that the file was deleted.
- Repair and rebuild failures preserve the active index and include a user-readable recovery action.
- No maintenance operation follows symlinks, enters package contents, or changes indexed files.

## Performance Requirements

- Keep the existing 60 ms input debounce.
- On the one-million-row synthetic index, selective first-page searches for every supported sort should target warm p95 below 50 ms with a 200-row result window.
- Empty-query Modified and Size sorts must use covering or ordered indexes and keyset pagination.
- Index Center must not execute aggregate counts on every SwiftUI render. Health snapshots are explicitly refreshed and cached for at least one second.
- Opening Index Center should target under 250 ms on the synthetic one-million-row database.
- Recent and saved search persistence is bounded and must not touch SQLite.

## Delivery Order

### V1.1A — Index trust foundation

- Schema migration.
- Per-scope state and persisted timestamps.
- Durable issue history.
- Index Center overview and location rows.
- Targeted rescan.
- Volume availability and offline result badges.
- Verify Index.

### V1.1B — Search productivity

- Sort-aware requests and keyset cursors.
- Sortable result columns.
- Recent and saved searches.
- Structured filter tokens.
- Size filter.
- Safe multi-selection and multi-file Quick Look.

### V1.2 — Maintenance completion

- Rebuild Search Index.
- Atomic Rebuild Entire Index with rollback.
- Idle pruning of resolved issues.
- Persisted table column visibility, widths, and order if SwiftUI Table customization remains reliable on macOS 14.

## Testing Strategy

### Core tests

- Parse valid and invalid size forms, Unicode queries, quotes, and mixed filters.
- Verify literal sort order and cursor boundaries for every sort mode, including equal values and concurrent inserts.
- Migrate a real version 1 fixture to version 2 without row, FTS, scope, generation, or checkpoint loss.
- Coalesce, resolve, retain, and prune issue records.
- Verify health counts, timestamps, quick check, FTS integrity, and failure reporting.
- Confirm cancelled targeted scans retain the last completed generation.
- Confirm offline volumes retain entries and mismatched volume identities do not resume automatically.

### App-support tests

- Recent searches are bounded, deduplicated, and recorded only after successful current searches.
- Saved searches survive atomic-store corruption through last-good recovery.
- Stale search and health tasks cannot overwrite newer state.
- Multi-selection actions enforce their caps and report consolidated failures.
- Index Center state is derived correctly from mixed scope states.

### Performance and UI verification

- Extend the 100,000-row regression to every sort and size filter.
- Extend the opt-in one-million-row benchmark to record p50 and p95 per sort.
- Exercise saved/recent searches, token removal, sorting, multi-selection, Quick Look, per-scope rescan, offline volume transitions, verification, and repair in an isolated QA home.
- Re-run strict codesign, ZIP integrity, isolated installation, `/Applications` executable hash comparison, and `git diff --check`.

## Acceptance Criteria

- Search remains filename, path, and metadata only.
- Every enabled scope has an independent, understandable state.
- Users can identify why a scope is stale without reading logs.
- A failed or cancelled rescan or rebuild does not destroy the last usable index.
- Saved and recent searches recover from a corrupt primary file.
- All sort modes paginate without duplicates or omissions in deterministic tests.
- Space Quick Look, Enter Open, Command-C, and sidebar filter workflows continue to work with multi-selection.
- One-million-row warm selective search p95 remains below the 50 ms target for all supported sort modes.
