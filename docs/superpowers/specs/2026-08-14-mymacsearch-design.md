# MyMacSearch V1 Design

Date: 2026-08-14
Status: Approved product design; implementation not started

## Summary

MyMacSearch is a native macOS filename and path search utility inspired by the
speed and density of Windows Everything without attempting to reproduce its
NTFS-specific indexing. V1 builds its own metadata index from user-approved
locations, stores it in SQLite FTS5, and maintains it with FSEvents.

V1 searches file and directory names, extensions, paths, kinds, modification
dates, and sizes. It does not read file contents and does not provide OCR, PDF
body search, Spotlight-backed primary search, fuzzy matching, file deletion, or
file modification.

## Goals

- Show a useful search window immediately when the app opens.
- Return ordinary warmed search results with perceptually immediate latency.
- Remain responsive while scanning and updating an index that can grow to one
  million entries.
- Make the indexed locations, exclusions, permission failures, and current
  index state visible to the user.
- Treat inaccessible, missing, moved, disconnected, and replaced paths as
  normal filesystem conditions rather than crashes.
- Provide only read-only result actions: Open, Reveal in Finder, Copy Path,
  Open in Terminal, Open in MyMacFinder, and Quick Look.
- Produce a personal-use signed app bundle and integrity-checked installer ZIP
  that can be safely installed at `/Applications/MyMacSearch.app`.

## Non-goals

- File content, OCR, image text, archive content, or PDF body search
- Spotlight as the primary index or query engine
- NTFS-style low-level filesystem journal indexing
- Fuzzy or semantic search
- A background helper, launch agent, login item, or menu bar item
- Searching external or network volumes without explicit user opt-in
- Any action that deletes, renames, moves, or modifies indexed files
- Public distribution, Developer ID signing, notarization, auto-update, or App
  Store sandboxing

## Chosen Approach

V1 uses one regular Dock application with three Swift Package targets:

```text
MyMacSearchCore
    metadata models, policies, query parser, scanner, SQLite/FTS5,
    FSEvents interpretation, index reconciliation

MyMacSearchAppSupport
    index coordinator, observable view models, settings, onboarding,
    result actions, Quick Look session, global shortcut coordination

MyMacSearchApp
    SwiftUI application, AppKit result table, resources, commands
```

This follows the existing MyMacStats and MyMacClean target separation. The
Core target does not depend on SwiftUI or AppKit UI. AppSupport owns UI-facing
state and adapters. The executable target remains small.

A separate helper process was rejected for V1 because continuous indexing
while the main app is closed does not justify the additional IPC, permission,
login-item, lifecycle, testing, and packaging complexity. A monolithic target
was rejected because it would couple database, filesystem, and UI behavior and
make failure-path testing harder.

## Platform and Dependencies

- Swift 6 language mode
- SwiftUI and AppKit
- macOS 14 or later
- System `libsqlite3`, linked directly; no third-party SQLite package
- CoreServices FSEvents
- QuickLookUI for Space-bar preview
- Carbon `RegisterEventHotKey` for a configurable global shortcut without an
  Accessibility permission requirement

The development Mac currently reports SQLite 3.43.2 with FTS5 enabled, and an
actual FTS5 trigram table creation probe succeeds. This machine-level check is
not treated as proof for every supported Mac, so the app performs the same
runtime capability probe before opening or creating the production index.

## Application Data

The derived index and its support data live under:

```text
~/Library/Application Support/MyMacSearch/
  index.sqlite3
  index.sqlite3-wal
  index.sqlite3-shm
```

Preferences store selected scopes, exclusions, hidden-item policy, hotkey, and
presentation settings. The app writes only its own preferences and derived
index. It never writes to indexed files or directories.

Database initialization enables WAL mode, foreign keys, a 2,000 ms busy
timeout, and an explicit schema version. One writer actor owns all mutations.
Search uses a separate read connection so batch indexing cannot monopolize the
query path. Connections and prepared statements are never shared concurrently.

## Index Schema

The logical schema contains:

- `scopes`: selected root, volume identity and type, enabled state, scan state,
  completed generation, last FSEvent ID, and last error
- `entries`: original display path and name, normalized searchable path and
  name, parent path, extension, kind, size, modification date, directory,
  symlink, package and hidden flags, device/inode hints, scope, and scan
  generation
- `entries_fts`: external-content FTS5 index over normalized name and path,
  using the trigram tokenizer
- `scan_issues`: at most 500 recent skipped-path records per scope with category
  and message; aggregate skip and permission counts are stored separately

The canonical row identity is an internal integer. Path is unique within the
index. Device and inode are non-unique hints because hard links may legitimately
give several paths to the same filesystem object. Original spelling is kept for
display and actions; separate normalized strings support case-insensitive,
canonical Unicode search.

Entry-table and FTS changes occur in the same transaction. Full-scope scans use
a new scan generation. Entries from an older generation are pruned only after
the new generation completes successfully, so cancellation or a permission
failure cannot erase the last completed view of a scope.

## FTS5 Capability Failure

At startup, a temporary in-memory connection must successfully:

1. Report `sqlite_compileoption_used('ENABLE_FTS5') = 1`.
2. Create an FTS5 virtual table.
3. Create an FTS5 table using `tokenize='trigram'`.
4. Insert and retrieve a punctuation-containing substring through a bound,
   escaped query.

If any step fails, indexing and search remain disabled, index state becomes
`Error`, and the UI explains that this macOS SQLite build lacks the required
FTS5 capability. The app does not silently switch to Spotlight or an unbounded
filesystem scan.

## First-run Onboarding

No deep scan starts before the user reviews and confirms its scopes and
exclusions. The first-run screen recommends existing directories among:

- `~/Desktop`
- `~/Documents`
- `~/Downloads`
- `~/Developer`
- `~/Projects`

Missing recommended directories are not created. The user can add or remove
locations before confirming. Volumes identified as external or network-backed
show an explicit opt-in warning and are never preselected.

The screen also explains that macOS privacy controls may block some selected
locations, that the app will continue past unreadable directories, and that
Full Disk Access should be granted only if the user wants those protected
locations indexed.

## Traversal and Exclusion Policy

Exclusions are evaluated before descending into a directory. Default excluded
locations and directory names include:

- `/System`
- `/Library`
- `~/Library/Caches`
- `.git`
- `.build`
- `node_modules`
- `DerivedData`

The policies are intentionally separate:

- Symlinks: index the symlink entry itself; never follow it during traversal.
- Packages and app bundles: index the package as one result; do not descend.
- Hidden items: excluded by default; the user may enable them in Settings.
- External volumes: index only when explicitly selected.
- Network volumes: index only when explicitly selected and report disconnects
  as unavailable scopes rather than global errors.

Built-in safety exclusions remain distinguishable from user exclusions in the
UI. Changing a traversal-affecting setting schedules reconciliation for only
the affected scopes.

The scanner runs off the main actor and checks cancellation before enumeration,
between entries, before metadata reads, before sending a batch, and before
committing a batch. Metadata writes are batched, initially targeting 1,000
entries per transaction and adjusted only from benchmark evidence.

Progress reports exact scanned-entry and skipped-entry counts, current path,
completed scopes, and an explicitly labelled estimated directory progress.
That estimate is `processed directories / (processed + currently queued
directories)` and may adjust as more descendants are discovered. The app does
not claim an exact file percentage because obtaining a true total would require
a second full traversal. Committed batches remain searchable during the scan,
while the visible state continues to make partial coverage explicit.

## FSEvents and Reconciliation

Each enabled local scope has an FSEvents stream using file-level event flags.
Events are collected off the main actor, coalesced for 250 ms, then submitted
as a bounded update batch.

To close the scan/watch handoff gap, the coordinator starts a bounded event
buffer and records its checkpoint immediately before beginning a scope scan.
After the scan generation commits, buffered events are applied before the scope
enters `Watching`. Buffer overflow or any dropped-event flag discards guesses
and schedules reconciliation. This prevents a create, move, or delete that
happens during the initial scan from being silently missed.

- Created or modified paths are re-read and upserted if policy allows.
- Removed paths delete the corresponding entry and indexed descendants.
- Renames are reconciled from the affected old/new parents; device/inode hints
  may optimize matching but are not correctness keys.
- `MustScanSubDirs`, dropped events, wrapped IDs, root changes, and an invalid
  persisted checkpoint mark the scope for reconciliation rather than guessing.
- App pause stops streams after persisting their latest safe checkpoints.
- Resume and next launch request events since the persisted checkpoint. If the
  checkpoint cannot provide a complete history, the scope is rescanned.
- External or network scope reconnect always performs a reconciliation scan
  before returning to `Watching`.

The database is the source of search truth; FSEvents is a change notification
mechanism, not a complete journal that the app assumes can never lose events.

## Index States

The user-visible primary states are exactly:

- `Initial scan`
- `Watching`
- `Paused`
- `Permission needed`
- `Error`

`Permission needed` is used when one or more selected scopes are materially
blocked while other readable scopes may continue working. The status bar shows
coverage and skip counts so partial coverage is not mistaken for a complete
index. Disconnected opt-in volumes appear as unavailable scope details without
turning healthy local scopes into `Error`.

macOS has no reliable universal preflight for Full Disk Access. Guidance is
therefore based on actual permission-denied results. The recovery action opens:

```text
x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles
```

After the user changes permission, Retry reconciles the affected scope.

## Query Language

Whitespace-separated terms are combined with AND. Unqualified terms match
normalized name or path. Supported filters are:

- `ext:swift`: exact normalized extension
- `kind:pdf`: normalized file kind
- `path:Downloads`: path substring
- `name:report`: filename substring
- `modified:today`: current local calendar day
- `modified:7d`: rolling seven-day interval ending now

Quoted values may contain spaces. Filter names are case-insensitive. Unknown
filters, missing values, unterminated quotes, invalid duration values, and
unsupported kind values produce a parser error shown beneath the search field;
they never reach SQLite as raw FTS syntax.

Kinds in V1 are `folder`, `application`, `pdf`, `image`, `video`, `audio`,
`archive`, `code`, `document`, and `other`. Classification uses metadata and a
small deterministic extension mapping. `ext:` remains available when the user
wants the exact suffix instead of a group.

Three-or-more-character text uses escaped, bound trigram MATCH expressions for
substring search. One- and two-character text uses an indexed filename-prefix
path with a bounded result window; V1 does not promise arbitrary mid-token path
substrings for such short terms. Dots, quotes, hyphens, apostrophes, wildcard
characters, decomposed Unicode, and Korean text receive explicit parser and
database tests.

## Search Execution and Performance

Search input is debounced by approximately 60 milliseconds. Every request has a
generation token. Cancellation and generation checks occur before querying,
after the database returns, and before publishing rows so a slow old query can
never overwrite a newer query.

The initial result window is capped at 200 rows. Further navigation uses
keyset pagination based on the stable ranking and tie-break identity rather
than progressively larger `OFFSET` scans. The table creates rows lazily and
does not eagerly load icons for the full result set.

Default ranking favors:

1. exact filename match
2. filename prefix
3. filename substring
4. path substring
5. newer modification date
6. stable path tie-break

The release benchmark builds a one-million-entry temporary metadata index,
warms representative queries, and records p50 and p95 latency for free text,
name, path, extension, kind, and date-filter combinations. The acceptance
target is warmed p95 at or below 100 ms on the development Mac for ordinary
selective queries. Actual timings, hardware, database size, and exceptions are
recorded; the design does not claim identical latency on every volume or Mac.

## User Interface

The app launches as a normal Dock application. Its primary window uses a quiet,
dense macOS utility layout:

- large search field at the top
- scope and filter sidebar on the left
- central AppKit-backed results table
- bottom index status bar

The result columns are Name, Path, Kind, Size, and Modified. Columns support
native resizing. Default ordering is relevance; selecting a sortable column
explicitly replaces relevance ordering until the user restores Relevance.
The status bar shows primary state, exact scanned count, skip count, current
path, estimated progress, and a compact action for details or retry.

Keyboard behavior:

- Up/Down changes selection.
- Return opens the selected result.
- Space presents Quick Look when possible.
- Command-C copies the selected absolute path.
- Escape clears the query first, then hides the window when the query is empty.

The default global shortcut is Option-Space. It is configurable and can be
disabled. `RegisterEventHotKey` registration failure, including a shortcut
conflict, is shown in Settings without breaking ordinary app use. Invoking the
shortcut brings the existing search window forward and focuses/selects the
search field instead of creating duplicate windows.

V1 does not create a menu bar item.

## Result Actions

Every action revalidates the selected path immediately before handoff:

- Open: use `NSWorkspace`; surface failure.
- Reveal in Finder: use Finder selection; surface missing-path failure.
- Copy Path: write the original absolute path to the pasteboard.
- Open in Terminal: open a directory result itself or a file result's parent in
  Terminal.app; report a missing Terminal or launch failure.
- Open in MyMacFinder: locate bundle identifier `com.biglol.MyMacFinder`, pass
  the directory result or a file result's parent, and report not-installed,
  incompatible-version, or launch failure.
- Quick Look: present only the current selection and invalidate stale preview
  generations when selection or results change.

If a result no longer exists, the action reports that the item moved or was
removed and queues a safe index reconciliation. No external-launch failure is
silently ignored.

### MyMacFinder integration boundary

The current MyMacFinder app has no external folder-open handler. Satisfying this
action therefore requires a small, backward-compatible MyMacFinder change:

- add an application-level router for file URL open events sent by
  `NSWorkspace`
- accept only existing local directory URLs and reject non-file, missing, and
  regular-file inputs
- route a valid directory to the active pane through the existing ExplorerStore
  navigation path
- expose a boolean Info.plist capability marker so MyMacSearch can distinguish
  a compatible installation from an older version that would launch but ignore
  the requested directory
- add focused router, validation, active-pane, unavailable-path, and repeated
  event tests without changing MyMacFinder's ordinary startup behavior

MyMacSearch does not automate MyMacFinder's UI and does not request
Accessibility permission. The compatible MyMacFinder build must pass its full
test suite, warning-strict build, packaging, signature, executable-hash, and
installed-path checks before the integration is reported as working. Its
personal ZIP is refreshed in `downloads/MyMacFinder/` so the documented
download is not older than the installed integration build.

## Error and Recovery Design

- Per-path metadata and permission errors increment skip counters and add a
  bounded issue record; they do not abort unrelated scopes.
- Scope-root permission failure changes coverage to `Permission needed`.
- SQLite busy errors receive a bounded retry; persistent failures become
  `Error` without discarding the last displayed results.
- A corrupt index is preserved with a timestamped diagnostic name. Rebuild
  creates a new database and promotes it only after schema and FTS validation.
- A cancelled scan becomes `Paused` and retains committed batches. Resume
  starts a fresh incomplete generation and prunes only after completion.
- A disappeared or disconnected volume preserves its configuration and reports
  unavailable until reconnect or user removal.
- All user-facing errors include the failed operation and a useful recovery
  action when one exists.

## Test Strategy

### MyMacSearchCoreTests

- FTS5/trigram capability success and explicit failure
- schema creation and migration behavior
- insert, update, rename reconciliation, delete, descendant delete, and
  generation-based pruning
- transaction rollback and busy handling
- all supported filters, combinations, quoting, invalid syntax, punctuation,
  Unicode normalization, and parameter binding
- kind classification and exact extension behavior
- built-in/user exclusions and scope boundaries
- symlink no-follow, package no-descend, and hidden-item settings
- scanner cancellation at each meaningful boundary
- inaccessible directory and metadata-read skip accounting through injected
  filesystem clients
- FSEvents flag interpretation, coalescing, checkpoint persistence, dropped
  event fallback, reconnect, and reconciliation planning
- hard-link/device/inode cases without path collapse

### MyMacSearchAppSupportTests

- state transitions among Initial scan, Watching, Paused, Permission needed,
  and Error
- progress throttling and partial-coverage presentation
- query generation and stale result suppression
- selection and pagination continuity
- global shortcut conflict and single-window activation
- Open, Reveal, Copy, Terminal, MyMacFinder, Quick Look, missing-path, and
  missing-application and incompatible-MyMacFinder behavior through injected
  adapters
- Full Disk Access guidance and settings URL

### Integration and Performance

- temporary real directory initial scan plus create/update/move/delete events
- cancellation and resume without incorrect generation pruning
- external/unavailable scope simulation at the policy boundary
- 100,000-entry regular regression dataset
- one-million-entry release-mode benchmark with p50/p95 reporting

All normal tests run with `swift test`. The one-million-entry benchmark is also
part of release verification and may use a dedicated environment switch to
avoid accidental debug-mode timing claims; release completion requires running
it explicitly and recording its output.

### Manual macOS QA

- first-run selection and no-scan-before-confirmation
- visible initial progress while typing/searching remains responsive
- global shortcut focus and shortcut-conflict presentation
- keyboard navigation, Return, Space, Command-C, and Escape
- all external actions, including explicit failure UI
- Full Disk Access settings button and retry flow
- pause/resume, relaunch catch-up, and disconnected opt-in volume presentation

Automated evidence and manual GUI evidence are reported separately.

## Packaging and Installation

The repository adds:

```text
MyMacSearch/scripts/build-app-bundle.sh
MyMacSearch/scripts/package-personal.sh
MyMacSearch/scripts/check-distribution.sh
```

The app bundle uses:

- bundle name: `MyMacSearch`
- bundle identifier: `com.biglol.MyMacSearch`
- executable: `MyMacSearchApp`
- category: Utilities
- minimum system version: 14.0

`build-app-bundle.sh` performs a release build, constructs the bundle from
explicit resources and Info.plist, applies an ad-hoc signature, and runs strict
signature and plist validation.

`package-personal.sh` creates:

```text
MyMacSearch/dist/MyMacSearch-personal-mac.zip
```

The archive contains the app, `Install MyMacSearch.command`, and a concise
personal-use README. ZIP creation is followed by `unzip -tq`.

`check-distribution.sh` extracts into a fresh temporary directory, verifies the
packaged signature and Info.plist, adds a simulated quarantine attribute, runs
the installer into a temporary Applications directory without launching, then
checks quarantine removal, strict signature validity, and executable hash
equality.

The real installation uses a unique same-volume staging path under
`/Applications`. It verifies the staged signature and executable hash before
publication. An existing MyMacSearch app is moved to a unique rollback path,
the staged app is renamed into place, and the new installation is verified
before the old bundle is moved to the user's Trash as a recoverable backup.
The installer never empties Trash and never removes application-support index
data.

After installation, verification records:

- ZIP SHA-256
- build, packaged, staged, and installed executable SHA-256
- strict codesign result
- bundle identifier, name, executable, version, and minimum OS
- installed executable path
- launched process's exact executable path and immediate-crash check

The final personal artifact is copied to:

```text
downloads/MyMacSearch/MyMacSearch-personal-mac.zip
```

The root README receives the app description, source link, download link,
quick-run command, minimum OS, and packaging command only after app and artifact
verification succeed.

## Completion Gates

Implementation is complete only when all of the following are true:

1. Full `swift test` passes for MyMacSearch and for the minimally changed
   MyMacFinder integration.
2. Warning-strict release build passes.
3. Index create/update/delete/reconciliation, permission failure, and parser
   coverage passes.
4. One-million-entry benchmark is run in release mode and results recorded.
5. App bundle and personal ZIP are regenerated from the reviewed source.
6. Bundle plist, strict codesign, and ZIP integrity pass.
7. Temporary install simulation passes.
8. `/Applications/MyMacSearch.app` is installed through verified staging and
   rollback handling.
9. Build/package/install executable hashes match and bundle/process information
   is confirmed.
10. Required manual keyboard, shortcut, Quick Look, action, permission, and
    lifecycle QA is recorded with unverified boundaries called out.
11. `git diff --check` passes and every changed file is reviewed before commit.
12. Build caches, `.build`, `DerivedData`, temporary dist contents, and other
    unintended artifacts are absent from the commit; only the approved download
    ZIP is retained as a distribution artifact.

## Deferred Work

The following require a later design and are not implementation stretch goals:

- menu bar item
- background helper or login item
- public Developer ID/notarized distribution
- fuzzy, semantic, content, OCR, PDF-body, or archive-content search
- Finder Tags and Spotlight fallback
- file mutation actions
