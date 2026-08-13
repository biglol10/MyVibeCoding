# MyMacClean Safety and Utility Expansion Design

Status: implemented and verified on 2026-08-13.

Verification completed with 204 passing Swift tests, a production build, a
strict app-signature check, a valid DMG checksum, and real release-app checks
covering permission guidance, scan coverage details, App Reset confirmation,
session-only Large Files settings, refresh behavior, startup items, developer
caches, orphan files, and expandable deletion error history. Destructive UI
checks used disposable fixtures only.

## Context

MyMacClean currently provides five personal cleanup workflows: Applications,
Orphan Files, Large Files, Developer Cache, and Startup Items. The existing
release is review-first, uses Trash by default, verifies every destructive
attempt, and records local receipts.

The current automated suite passes, but source review found safety and trust
gaps that the existing tests do not cover:

- Bundle identifier matching accepts an identifier as an arbitrary substring,
  so a similarly named but unrelated identifier can be marked safe.
- Single-word app names can match unrelated package names that merely contain
  the same token.
- App and leftover scanners silently skip inaccessible roots, so a partial
  scan can look complete.
- User-file cleanup policies can become too broad if a future caller provides
  a root such as `/`, `/Users`, `/Library`, or `/Applications`.
- Application discovery only checks direct children of configured roots.

This expansion fixes those gaps and adds features that reuse the current safe
deletion pipeline instead of introducing privileged or automatic cleanup.

## Goals

1. Make related-file matching conservative enough that similar names and
   identifiers are not selected automatically.
2. Make deletion policies fail closed outside explicitly supported roots.
3. Report incomplete scan coverage in the UI with actionable permission
   guidance.
4. Discover application bundles inside ordinary subfolders without scanning
   inside application packages.
5. Add App Reset, which removes reviewed app data while preserving the app
   bundle.
6. Let Large Files scan a user-selected folder while keeping selection manual
   and deletion Trash-only.

## Non-Goals

- Privileged helper installation.
- Bypassing Full Disk Access, administrator authorization, SIP, or TCC.
- Automatic cleanup or scheduled cleanup.
- Permanent deletion for App Reset or Large Files.
- Duplicate-file detection, secure shredding, malware scanning, RAM cleaning,
  or Docker deletion.
- Following symlinks outside an approved cleanup root.
- Persisting arbitrary folder access across launches in this phase.

## Safety Invariants

- All destructive operations require explicit item selection and typed
  confirmation.
- Applications and Orphan Files remain Trash-first; permanent deletion remains
  an explicit advanced option only for those existing workflows.
- App Reset and Large Files are Trash-only and do not expose force deletion.
- Protection is checked when candidates are scanned and again immediately
  before execution.
- A candidate outside the active allowlist is protected by default.
- `/`, `/Users`, `/Applications`, `/Library`, `/System`, `/bin`, `/sbin`,
  `/usr`, `/private`, and `/var` cannot be configured as broad user-file
  cleanup roots.
- A selected `.app` bundle under `/Applications` or the current user's
  `~/Applications` remains an allowed uninstall target, except for the running
  MyMacClean bundle and other explicit protected roots.
- Symlink resolution is used for policy decisions. Deletion acts on the
  selected directory entry and never intentionally traverses a symlink target.
- Every deletion or reset attempt is verified and recorded, including partial
  and failed attempts.
- An inaccessible scan root is reported as incomplete coverage, not treated as
  an empty successful root.

## Design

### 1. Conservative Candidate Matching

`CandidateMatcher` will treat a bundle identifier as strong evidence only when
it is bounded by path or identifier separators. Examples:

- `com.example.Editor` matches `com.example.Editor.plist`.
- `group.com.example.Editor` matches `com.example.Editor`.
- `com.example.Editor.helper` matches `com.example.Editor`.
- `com.example.EditorPlus` does not match `com.example.Editor`.
- `xcom.example.Editor` does not match `com.example.Editor`.

For a single-token display or executable name, a candidate must have the same
complete token sequence. `Cursor` can match a folder named `Cursor`, but it
cannot match `cli-cursor`, `cursor-theme`, or `restore-cursor`. Multi-token app
names retain contiguous full-sequence matching.

Strong bundle evidence can remain default-selected. Exact name evidence remains
Review unless the existing safety scorer can prove it is inside a known cleanup
root. Weak or ambiguous matches remain unselected.

### 2. Fail-Closed Cleanup Policies

`ProtectionPolicy` will allow app cleanup only for:

- selected `.app` bundles under `/Applications`;
- selected `.app` bundles under the current user's `~/Applications`;
- known user Library app-data roots already enumerated by the scanner;
- test-only or explicitly supplied temporary roots used by the existing local
  test harness.

All other paths are protected unless a narrower purpose-specific policy is
used. Existing protected user-content roots and the running MyMacClean bundle
remain protected.

`UserFileCleanupPolicy` will validate its configured roots. Broad system or
multi-user roots are rejected from its internal allowlist. A file is deletable
only when its resolved path is a descendant of a validated active root and is
not under a blocked system location.

The policies will expose deterministic protected/not-protected behavior only;
UI-specific messages remain in the app-support layer.

### 3. Structured Scan Coverage

Core scanners that can partially succeed will return a structured result:

```swift
public struct ScanIssue: Equatable, Sendable {
    public let path: String
    public let message: String
    public let permissionRelated: Bool
}

public struct ScanResult<Value: Sendable>: Sendable {
    public let value: Value
    public let issues: [ScanIssue]
}
```

The first implementation covers:

- application discovery roots;
- related-file roots;
- orphan-file roots;
- Large Files enumeration roots and descendants;
- Developer Cache size calculation targets;
- Startup Items roots and malformed or unreadable plist files.

Missing optional roots are not issues. A root or item that exists but cannot be
listed, read, or measured is an issue. Duplicate issue paths are collapsed.

View models expose the latest issues and clear them before a new scan. A scan
with useful results and issues is a partial success. A scan where every existing
root failed still presents the issues rather than claiming that nothing was
found.

The UI shows a compact `Scan incomplete` banner with:

- the number of inaccessible or unreadable locations;
- an expandable list of paths and errors;
- Copy Details;
- Open Full Disk Access Settings when at least one issue is permission-related.

The banner appears only in the active workflow and does not use a modal alert
for non-fatal partial results.

### 4. Nested Application Discovery

Application discovery will enumerate configured roots recursively while
skipping hidden entries and package descendants. When an `.app` is found, it is
read as one application and the enumerator skips its descendants so embedded
helpers are not listed as installed apps.

Resolved bundle paths are deduplicated. A failure reading one app's metadata is
recorded as a scan issue and does not discard other discovered applications.
The existing exclusion of the running MyMacClean bundle remains in the view
model.

### 5. App Reset

The Applications inspector gains an `Uninstall` / `Reset Data` segmented
control after a related-file scan.

Reset Data behavior:

- The app bundle candidate is excluded and cannot be selected in reset mode.
- Eligible user-data candidates retain their evidence, safety badges, and
  manual selection controls.
- Protected candidates remain disabled. Risky candidates remain unselected by
  default and require explicit manual selection.
- The selected app must not be running.
- Confirmation requires the exact text `RESET`.
- Reset always moves items to Trash.
- Permanent deletion and force-unlock controls are hidden.
- The app bundle stays installed and selected after a successful reset.
- Verified-deleted data candidates are removed from the inspector and the app
  is rescanned so stale rows do not remain.

`DeletionAction` gains `appReset`. Reset receipts contain the selected data
candidates, execution results, and verification results. Delete History labels
the action as an app data reset and preserves the same expandable error logs.
Success, partial success, and failure use the existing toast infrastructure.

`DeletionExecutor.execute` gains a `requiredConfirmation` argument whose
default remains `DELETE`. Existing uninstall and cleanup callers therefore keep
their current behavior. App Reset passes `RESET`, and the executor compares the
typed text before any filesystem operation. Receipts continue to store only the
boolean match result.

### 6. User-Selected Large Files Folder

The Large Files toolbar gains a folder chooser using the native macOS open
panel. The selected folder becomes the active scan root for the current app
session.

Rules:

- Only one folder is active at a time.
- The default remains top-level `~/Downloads`.
- Changing the folder clears previous candidates, selection, report, and scan
  issues before scanning.
- Results are never auto-selected.
- The current 500 MB threshold remains fixed in this phase.
- The current default remains non-recursive. The UI adds an `Include
  Subfolders` toggle that is off by default.
- Package descendants and hidden files remain skipped.
- The deletion policy is rebuilt from the exact active root and rejects broad
  unsafe roots.
- Cleanup remains Trash-only and requires `DELETE`.

The chosen folder is not persisted. This avoids stale access assumptions and
security-scoped bookmark complexity in a non-App-Store personal build.
Choosing a rejected broad root shows a non-destructive validation error and
does not replace the current valid root.

### 7. Receipt Durability

Receipt append operations will close file handles with `defer`, even if seek or
write fails. Malformed lines continue to be skipped so one damaged receipt does
not hide valid history. Receipt-writing failures remain visible without
changing a successfully verified filesystem result into a deletion failure.

No receipt stores typed confirmation text or file contents.

## Data Flow

1. The active view model starts a scan and clears stale candidates, selection,
   reports, and scan issues.
2. The core scanner returns values plus structured issues.
3. The view model publishes usable values and coverage issues independently.
4. The user reviews and explicitly selects candidates.
5. The planner filters protected candidates and creates a plan.
6. The executor rechecks the purpose-specific policy, performs Trash movement,
   and records per-path results.
7. The verifier checks every planned path.
8. The view model reconciles only verified-deleted paths, persists a receipt,
   and presents a success, partial, or failure toast.
9. Applications refresh or rescan according to the active operation so stale
   rows and details are not retained.

## Error Handling

- Partial scan errors are non-modal coverage issues.
- A total discovery failure still leaves the app usable and shows every known
  failed root.
- Deletion-policy rejection is a per-path protected result and is written to
  history.
- Permission failures offer the existing Full Disk Access settings action.
- Finder Automation fallback remains limited to `.app` bundles moved to Trash.
- App Reset never invokes Finder Automation because it excludes the app bundle.
- A failed receipt write is reported separately from deletion verification.
- Cancellation of the native folder chooser changes no state.

## UI Direction

The existing restrained Finder/System Settings-style inspector remains. New UI
uses native segmented controls, disclosure groups, banners, and the open panel.
No dashboard cards, marketing panels, or decorative color treatment are added.

The scan coverage banner is visually secondary to the selected item and
primary action, but uses an amber warning icon and readable body text. Long
paths use middle truncation in the collapsed state and full selectable text in
the disclosure.

## Testing

All behavior changes use red-green-refactor development.

Core tests will cover:

- bounded bundle identifier matching and similar-identifier rejection;
- rejection of unrelated single-token names;
- fail-closed app cleanup outside known roots;
- rejection of broad user-file roots;
- scan issue collection without dropping successful results;
- recursive app discovery without embedded helper duplication;
- Large Files issue reporting and recursive toggle behavior;
- receipt file-handle cleanup behavior where it can be observed reliably.

App-support tests will cover:

- scan issue state replacement and clearing;
- App Reset plan excludes the app bundle;
- `RESET` confirmation mismatch fails safely;
- running apps block reset;
- verified reset keeps the app but removes stale data rows;
- reset receipts use `appReset`;
- changing the Large Files root invalidates old results and rebuilds deletion
  protection;
- partial scans do not display an empty-success state.

Manual verification will cover:

- build and launch the real app bundle;
- scan Applications and confirm nested apps are not duplicated by helpers;
- induce one inaccessible temporary scan root and inspect the coverage banner;
- reset a disposable fixture app and verify its bundle remains while selected
  test data moves to Trash;
- select a temporary Large Files folder, test recursive off/on behavior, and
  move a disposable fixture to Trash;
- inspect Delete History and error expansion;
- rebuild the personal DMG and verify its signature and disk image integrity.

## Acceptance Criteria

- Similar identifiers and unrelated single-word package names are not
  default-selected as app leftovers.
- Deletion cannot proceed outside the current workflow's validated roots.
- Partial scans are visibly marked with path-level diagnostic information.
- Apps inside ordinary application subfolders appear once; embedded helpers do
  not appear as separate installed apps.
- App Reset preserves the app bundle, requires `RESET`, is Trash-only, verifies
  results, refreshes the inspector, and records history.
- Large Files can scan one user-selected folder without persisting access or
  auto-selecting results.
- Existing uninstall, orphan cleanup, developer cache, startup item, permission,
  toast, history, build, and personal DMG flows continue to pass verification.
