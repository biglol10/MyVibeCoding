# MyMacClean Personal Cleaner Design

## Context

MyMacClean is already a native SwiftUI app with working application discovery,
related-file scanning, orphan leftover scanning, deletion verification, deletion
receipts, and delete history. The app should now become useful as a personal
BuhoCleaner replacement without copying every commercial cleaner feature.

The selected product direction is safety-first personal use:

- Default actions are review-first and reversible where possible.
- File cleanup moves items to Trash by default.
- Permanent deletion remains an explicit opt-in inside the confirmation sheet.
- Startup item changes start with reversible user LaunchAgent disable/enable.
- System-owned startup items and protected paths are visible but read-only.

## Goal

Build five personal-use cleanup pillars well enough for daily use:

1. Application uninstall.
2. Orphan leftover cleanup.
3. Large file review.
4. Developer cache cleanup.
5. Startup item management.

This is not a one-click system cleaner. The app should help the user find,
understand, and safely remove items after explicit review.

## Non-Goals

- Malware scanning.
- RAM cleaning.
- Duplicate file detection in this phase.
- Secure shredder in this phase.
- Privileged helper installation.
- Automatic background cleanup.
- One-click deletion of broad system junk.
- Deleting system LaunchAgents or LaunchDaemons in the first startup-items
  implementation.

## Safety Rules

All five pillars share these rules:

- Never delete without an explicit selected item list.
- Never default-select risky or protected items.
- Move to Trash by default for file cleanup.
- Keep permanent deletion behind the existing confirmation opt-in.
- Recheck protection policy at execution time.
- Record receipts for destructive cleanup attempts.
- Show path-level failures instead of hiding them behind generic alerts.
- Prefer reveal/copy actions for uncertain items.
- For app-related cleanup, keep user documents, desktop, downloads, pictures,
  movies, music, iCloud document roots, system roots, and the running app
  bundle protected.
- For user-file cleanup such as Large Files, allow explicit Trash movement only
  for user-selected files inside the active scan roots. Never auto-select these
  files, never include app packages by default, and keep system roots protected.

## Product Scope

### 1. Applications

The existing Applications screen remains the main uninstall workflow.

Current behavior to preserve:

- Discover installed apps.
- Filter and sort apps.
- Scan app bundle plus related Library files.
- Show evidence, safety, and selection state per candidate.
- Move selected items to Trash by default.
- Allow permanent deletion only when the user opts in.
- Verify deletion and record a receipt.
- Refresh the list and clear stale details when the selected app is removed.

Improvements in this phase:

- Rename stale copy that still implies permanent deletion.
- Add clearer empty states when a scan has not run.
- Keep uninstall and leftover cleanup receipts visually consistent.
- Keep tests around post-delete list refresh and detail clearing.

### 2. Orphan Files

The existing Orphan Files screen remains the leftover cleanup workflow.

Current behavior to preserve:

- Scan known user Library cleanup roots.
- Group leftovers by inferred bundle identifier.
- Exclude currently installed apps and the running MyMacClean bundle.
- Avoid weak name matches such as generic development packages.
- Require explicit selection before cleanup.
- Remove verified-deleted groups from the UI.
- Record cleanup receipts.

Improvements in this phase:

- Add group-level select/deselect controls.
- Add Finder reveal and copy-path actions.
- Surface scan coverage limitations when roots are inaccessible.
- Keep LaunchAgent leftovers manual-review by default.

### 3. Large Files

Purpose: find large files that are worth manual review.

Scanner:

- Scan user-selected roots, defaulting to the home directory.
- The first release should scan common review roots: Downloads, Desktop,
  Movies, Documents, and selected developer folders, but never auto-select
  results.
- Exclude system roots and app internals.
- Ignore package contents by default for `.app`, `.framework`, `.bundle`, and
  `.photoslibrary` packages.
- Return files above a configurable threshold, default 500 MB.

UI:

- Sidebar destination: Large Files.
- Table columns: name, size, modified date, path, kind.
- Filters: minimum size, root, file kind, older-than.
- Sort: size descending, modified date, path.
- Actions: Reveal in Finder, Copy Path, Move Selected to Trash.
- No default selection.

Deletion:

- Reuse `DeletionExecutor`, `DeletionVerifier`, and receipt infrastructure.
- Use a new receipt action such as `largeFileCleanup`.
- Move to Trash by default.

### 4. Developer Cache

Purpose: reclaim space from caches that can be regenerated.

Initial targets:

- Xcode DerivedData: `~/Library/Developer/Xcode/DerivedData`
- Xcode Archives: `~/Library/Developer/Xcode/Archives`
- Xcode iOS DeviceSupport: `~/Library/Developer/Xcode/iOS DeviceSupport`
- SwiftPM cache: `~/Library/Caches/org.swift.swiftpm`
- npm cache: `~/.npm`
- yarn cache: `~/Library/Caches/Yarn`
- pnpm store: `~/Library/pnpm/store`
- CocoaPods cache: `~/Library/Caches/CocoaPods`
- Gradle cache: `~/.gradle/caches`
- Docker containers/images/build cache should be reported read-only first,
  because safe Docker cleanup is better handled through Docker commands.

Scanner:

- Detect known cache roots if they exist.
- Calculate recursive size.
- Classify each target:
  - Safe: DerivedData, SwiftPM cache, npm/yarn/pnpm caches.
  - Review: Archives, DeviceSupport, Gradle, CocoaPods.
  - Read-only: Docker in first release.
- Include explanation text for what will happen after deletion.

UI:

- Sidebar destination: Maintenance. In this phase the screen title becomes
  Developer Cache and the primary action becomes Scan Developer Caches.
- Group by tool: Xcode, Swift, Node, CocoaPods, Gradle, Docker.
- Show total reclaimable size.
- Default-select Safe groups only.
- Actions: Reveal in Finder, Copy Path, Move Selected to Trash.

Deletion:

- Reuse existing deletion pipeline.
- Record receipt action such as `developerCacheCleanup`.
- Do not run package-manager cleanup commands in the first release.

### 5. Startup Items

Purpose: show software that starts automatically and safely disable user-owned
startup plist entries.

Scanner:

- Read `~/Library/LaunchAgents`.
- Read `/Library/LaunchAgents`.
- Read `/Library/LaunchDaemons`.
- Parse plist fields: `Label`, `Program`, `ProgramArguments`, `RunAtLoad`,
  `KeepAlive`, `StartInterval`, `StartCalendarInterval`, `Disabled`.
- Detect file owner scope:
  - User item: under `~/Library/LaunchAgents`.
  - System-wide item: under `/Library/LaunchAgents` or `/Library/LaunchDaemons`.
- Infer owner app from label, program path, and bundle identifier evidence when
  available.

Actions:

- User LaunchAgents:
  - Disable by moving `name.plist` to `name.plist.mymacclean-disabled`.
  - Enable by moving the disabled file back.
  - Reveal in Finder.
  - Copy Path.
- System-wide items:
  - Read-only in the first release.
  - Reveal in Finder and Copy Path only.
- Delete startup plist:
  - Out of scope for first implementation. Disable is reversible and safer.

UI:

- Sidebar destination: Startup Items.
- Table columns: label, type, owner, enabled state, path, safety.
- Detail panel: parsed plist summary, program arguments, ownership evidence,
  and available actions.
- Badge states: Enabled, Disabled, Read-only, Missing Target.

Safety:

- Never disable root-owned or system-wide startup items in this phase.
- Never edit plist contents.
- Never call `launchctl` in the first release. File rename is simpler,
  reversible, and testable.
- Show a warning when an item target path is missing.

## Architecture

Continue the existing three-layer structure.

### MyMacCleanCore

New modules:

- `LargeFiles/LargeFileScanner.swift`
- `LargeFiles/LargeFileCandidate.swift`
- `DeveloperCache/DeveloperCacheScanner.swift`
- `DeveloperCache/DeveloperCacheCandidate.swift`
- `StartupItems/StartupItemScanner.swift`
- `StartupItems/StartupItem.swift`
- `StartupItems/StartupItemController.swift`

Shared infrastructure:

- Reuse `ProtectionPolicy` for app-related cleanup.
- Add a narrow `UserFileCleanupPolicy` execution policy for Large Files so
  explicitly selected files under the scan root can move to Trash without
  weakening app-uninstall protections.
- Reuse `FileSizeCalculator`.
- Reuse `DeletionExecutor`.
- Reuse `DeletionVerifier`.
- Extend `DeletionAction` with:
  - `largeFileCleanup`
  - `developerCacheCleanup`
  - `startupItemChange`

### MyMacCleanAppSupport

New view models:

- `LargeFilesViewModel`
- `DeveloperCacheViewModel`
- `StartupItemsViewModel`

Each view model owns:

- Scan state.
- Search/filter/sort state.
- Selected IDs.
- Last report or error message.
- Non-destructive reveal/copy data exposed to the UI.

### MyMacCleanApp

Navigation:

- Move Large Files from Roadmap to Current Release when implemented.
- Move Startup Items from Roadmap to Current Release when implemented.
- Use the existing Maintenance destination for Developer Cache in the first
  implementation: keep the enum value if that keeps changes smaller, but show
  the screen title as Developer Cache and the primary action as Scan Developer
  Caches.

UI pattern:

- Left/content column: scan controls, filters, result list.
- Detail column: selected item details, grouped candidates, action button.
- Use existing `DeleteActionButton` for file cleanup where possible.
- Use a separate reversible action button for Startup Items disable/enable.

## Implementation Phases

### Phase 1: Large Files

Deliver a complete Large Files screen:

- Scanner.
- View model.
- UI.
- Move selected files to Trash.
- Receipt and verification.
- Tests for scan filtering, sorting, protected roots, selection, and deletion
  reconciliation.

### Phase 2: Developer Cache

Deliver a complete Developer Cache screen under Maintenance:

- Known cache target scanner.
- Safety classification.
- Grouped UI.
- Default selection only for Safe items.
- Trash cleanup through existing deletion pipeline.
- Tests for missing roots, size calculation, safety classification, and
  deletion receipts.

### Phase 3: Startup Items

Deliver a Startup Items screen:

- Launch plist parser.
- Scanner for user and system locations.
- User LaunchAgent disable/enable by reversible rename.
- Read-only system items.
- Tests for plist parsing, classification, disable/enable, and read-only
  behavior.

### Phase 4: Existing Cleanup UX Polish

Refine Applications and Orphan Files after new modules are in place:

- Consistent receipts and report panels.
- Group-level selection for orphan leftovers.
- More visible permission/coverage notices.
- Finder reveal and copy-path actions where missing.

## Testing Strategy

Use TDD for each behavior.

Core tests:

- Large file scanner ignores app packages and protected roots.
- Large file scanner returns only files above threshold.
- Developer cache scanner classifies safe/review/read-only targets.
- Developer cache scanner calculates recursive sizes.
- Startup plist parser handles `Program`, `ProgramArguments`, `RunAtLoad`,
  `KeepAlive`, and malformed plists.
- Startup item controller disables and enables only user LaunchAgents.
- Startup item controller refuses system-wide items.
- Deletion receipts store new cleanup action types.

App-support tests:

- Large files view model scans, filters, sorts, selects, deletes, and clears
  verified-deleted items.
- Developer cache view model default-selects only safe cache groups.
- Startup items view model updates enabled/disabled state after controller
  actions.
- Each view model prevents duplicate operations while already scanning or
  applying changes.

Manual verification:

- Build and run `dist/MyMacClean.app`.
- Confirm Large Files can scan a temporary folder and move selected fixture
  files to Trash.
- Confirm Developer Cache reports real cache paths without auto-deleting review
  items.
- Confirm Startup Items can disable and re-enable a disposable user
  LaunchAgent.
- Confirm system LaunchDaemons are read-only.
- Run full `swift test`.
- Run `scripts/create-dmg.sh`.
- Run `codesign --verify --deep --strict`.

## Rollout Criteria

The feature set is acceptable for personal use when:

- Large Files, Developer Cache, and Startup Items have working scan screens and
  tested actions.
- No feature has one-click broad cleanup.
- File cleanup uses Trash by default.
- Startup item changes are reversible in the first release.
- Tests cover scanners, view models, deletion/verification, and startup item
  disable/enable.
- The app can be built into `dist/MyMacClean.app` and launched locally.

## Open Risks

- Full Disk Access may be required for complete scans in some user folders.
- Large-file scanning can be slow on huge directory trees.
- Developer cache safety differs by workflow; Xcode Archives and DeviceSupport
  can be valuable, so they remain review-only.
- Docker cleanup is best handled with Docker-aware commands, so first release
  should report Docker usage but not delete it.
- Startup item ownership inference can be imperfect; the UI must show evidence
  and avoid aggressive defaults.
