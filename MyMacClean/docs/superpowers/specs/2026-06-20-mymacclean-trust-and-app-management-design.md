# MyMacClean Trust and App Management Design

## Context

MyMacClean V1 is a native SwiftUI macOS app focused on installed application discovery, related-file scanning, explicit review, and permanent deletion. Recent manual testing exposed the product risk that matters most: users judge the app by whether deletion is visibly complete, not just whether `removeItem` succeeded.

This V2 design expands the app around deletion trust and app management. The selected scope is:

- Orphan Files Finder
- Post-delete automatic rescan and verification report
- App Reset
- Search, filter, and sort for installed apps
- Deletion receipts and logs
- Startup Items manager
- Safety score and match-reason explanations

These features should preserve V1's conservative deletion model: no silent destructive action, no broad privilege prompt at launch, and no claim that a scan is complete when permissions or safety rules prevented inspection.

## Product Goal

Make MyMacClean feel trustworthy enough for real daily use by showing what it found, why it believes files are related, what it deleted, what remains, and what needs user or permission action.

The app should become a practical app-management hub, but deletion correctness stays the core differentiator.

## Non-Goals

- Malware scanning.
- Duplicate-file detection.
- Full disk visualization.
- Cloud cleanup.
- Automatic background deletion.
- Privileged helper installation in this phase.
- Deleting system-protected items without explicit user review and macOS authorization.

## Recommended Build Order

### Milestone 1: Deletion Trust

1. Safety score and match-reason explanations.
2. Post-delete verification report.
3. Deletion receipts and logs.
4. Orphan Files Finder.

This milestone closes the main trust gap: a user should be able to prove whether an app and its known leftovers are gone.

### Milestone 2: App Management

5. Search, filter, and sort.
6. App Reset.

This milestone improves normal use after the deletion workflow is reliable.

### Milestone 3: Startup Control

7. Startup Items manager.

Startup Items is valuable, but it uses a different data model and action surface from app deletion. It should follow after the deletion modules have stable shared scan/report infrastructure.

## Architecture

The existing separation should continue:

- `MyMacCleanCore`: filesystem scanning, matching, planning, deletion execution, verification, journals, startup item parsing.
- `MyMacCleanAppSupport`: view models, navigation state, presentation models, filtering state.
- `MyMacCleanApp`: SwiftUI screens and native controls.

New core modules:

- `MatchEvidence`: structured reasons explaining why a candidate belongs to an app.
- `SafetyScorer`: converts evidence, path kind, protection state, and confidence into a user-facing safety level.
- `DeletionVerifier`: rescans planned paths after deletion and classifies each result.
- `DeletionReceiptStore`: appends durable deletion receipts and reads history.
- `OrphanFileScanner`: finds leftover files whose owning app bundle is no longer installed.
- `AppResetPlanner`: plans non-bundle cleanup for a selected app.
- `StartupItemScanner`: finds LaunchAgents, LaunchDaemons, and user-level login/background items where feasible without privileged helpers.

New app-support view models:

- `ApplicationFilterState`: search text, sort mode, and filters.
- `DeletionReportViewModel`: presents verification results and receipts.
- `OrphanFilesViewModel`: scans, groups, selects, and deletes orphan candidates.
- `AppResetViewModel`: prepares reset plans and executes reset confirmation.
- `StartupItemsViewModel`: lists startup items and exposes safe actions.

## Data Model Additions

### Match Evidence

Each related-file candidate should include structured evidence instead of only a short string:

- `evidenceType`: bundle identifier, exact app name, executable name, known vendor path, known updater name, receipt history, weak name match.
- `matchedValue`: the token or identifier that matched.
- `sourcePath`: the path segment or metadata source that produced the match.
- `strength`: strong, medium, weak.

The UI can still show a concise line, but tests should assert against structured evidence.

### Safety Score

Safety score should be deterministic and conservative:

- `safe`: bundle-id match or exact known app container in user Library.
- `review`: medium confidence, app-name match, updater folder, or nonstandard path.
- `risky`: protected path, shared vendor folder, weak token match, or path outside known cleanup locations.

Default selection rules:

- `safe` items are default-selected.
- `review` items are default-selected only when they have strong app identity evidence, such as bundle identifier or exact app display-name evidence, and live inside a known cleanup root.
- `risky` items are never default-selected.

### Verification Result

Post-delete verification should classify each planned item:

- `deleted`: path no longer exists.
- `stillExists`: path remains after deletion.
- `notFoundBeforeDelete`: path did not exist by execution time.
- `permissionDenied`: verifier could not inspect.
- `skipped`: user did not select or item was protected.

The report should include counts, total bytes planned, bytes confirmed removed where measurable, and a list of remaining paths.

### Deletion Receipt

Each completed deletion attempt should record:

- app name, bundle identifier, bundle path.
- timestamp.
- selected candidates.
- execution result per path.
- verification result per path.
- confirmation phrase used, stored as a boolean match result, not the typed text.
- app version where available.

Receipts should be local JSONL or JSON files under MyMacClean's Application Support directory. They are not a backup and cannot restore deleted files.

## Feature Designs

### 1. Orphan Files Finder

Purpose: find leftovers from apps that are no longer installed.

Scanner flow:

1. Discover currently installed bundle identifiers, display names, and executable names.
2. Scan known Library cleanup roots.
3. Identify candidates with app-like names or bundle identifiers that do not map to an installed app.
4. Group candidates by inferred app identity.
5. Assign safety scores and evidence.
6. Present groups for explicit review before deletion.

The scanner should prioritize precise bundle-id leftovers over loose name matches. It must avoid treating generic development packages such as `cli-cursor` or `restore-cursor` as leftovers for Cursor unless bundle-id evidence exists.

UI:

- Sidebar destination: `Orphan Files`.
- Summary row per inferred app: name, candidate count, total size, confidence.
- Detail panel shows every path, evidence, safety score, and checkbox.
- Primary action: `Delete Selected Leftovers`.

### 2. Post-Delete Verification Report

Purpose: make deletion outcomes visible and testable.

After deletion execution:

1. Run `DeletionVerifier` against the deletion plan.
2. Update the app list if the bundle is confirmed deleted.
3. Show a report panel instead of leaving stale candidates on screen.
4. Persist the receipt.

UI:

- Success state: `Deleted and verified`.
- Partial state: `Deleted with remaining items`.
- Failure state: `Deletion failed`.
- Remaining paths should have actions: `Reveal in Finder` and `Copy Path`.

The app must not present a deletion as fully complete if verification could not inspect one or more selected paths.

### 3. App Reset

Purpose: delete an app's user state while keeping the app bundle installed.

Reset plan:

- Exclude `.app` bundle candidate.
- Include cache, preferences, saved state, HTTP storage, WebKit storage, logs, containers, and application support when safety score permits.
- Show the same evidence and safety controls as deletion.

Confirmation:

- Use `RESET`, not the app name.
- The copy must clearly say the app bundle will remain installed.

UI:

- Add a segmented mode in the app detail area: `Uninstall` and `Reset`.
- Reset button label: `Reset App Data`.
- After reset, run verification and show a reset-specific receipt.

### 4. Search, Filter, and Sort

Purpose: make the installed app list usable at real scale.

Search:

- Match display name, bundle identifier, vendor hint, and path.

Filters:

- All apps.
- Large apps.
- Recently unused where metadata is available.
- Apps with scanned leftovers.
- User apps only.
- Apple apps hidden by default unless the user opts in.

Sort:

- Name.
- Size.
- Last opened where available.
- Related item count after scan.

The table should keep selection stable when filters change. If the selected app disappears due to a filter, the detail panel should show a clear empty state instead of stale candidates.

### 5. Deletion Receipts and Logs

Purpose: create an audit trail for destructive actions.

Delete History should become a real screen:

- List receipts by date.
- Search by app name or path.
- Show status: verified, partial, failed.
- Detail view shows execution and verification results.
- Provide `Copy Report` for support/debugging.

Receipts must not store sensitive file contents. Paths are acceptable because the app's function is local cleanup, but the user should be able to clear history.

### 6. Startup Items Manager

Purpose: show and manage software that starts automatically.

Initial scope:

- `~/Library/LaunchAgents`
- `/Library/LaunchAgents`
- `/Library/LaunchDaemons`
- Login/background items that can be read through available macOS APIs without private API dependency.

Actions:

- Disable user LaunchAgents by moving or renaming with a reversible marker.
- Enable previously disabled items.
- Delete selected startup plist only after explicit confirmation.
- Reveal in Finder.

Safety:

- System and root-owned items default to review or read-only unless the app has sufficient permission.
- Items should be grouped by owning app when bundle-id evidence exists.

UI:

- Sidebar destination: `Startup Items`.
- Table: name, type, owner app, enabled state, path, safety.
- Detail: plist label, program arguments, run conditions, evidence, actions.

### 8. Safety Score and Match Reasons

Purpose: reduce accidental deletion and make decisions understandable.

Every candidate row should show:

- safety badge: Safe, Review, Risky.
- evidence summary: for example, `Bundle ID match: com.example.app`.
- path kind: cache, preferences, support, saved state, launch agent.
- default selection state based on safety.

The user can expand a row to see full evidence. Risky items require manual selection and should display a short warning.

## UI Navigation

Sidebar should evolve from placeholders to real sections:

- Applications
- Orphan Files
- Delete History
- Startup Items

Roadmap-only placeholders can remain for features not in this scope, but selected features should have working screens.

Applications detail should support:

- app overview.
- scan results with evidence.
- mode switch for uninstall/reset.
- verification report after action.

## Error Handling

Permission errors must be first-class report items, not generic alerts.

Examples:

- Scan root inaccessible: show `Permission required` for that root.
- Deletion failed: show path-level error and keep candidate visible.
- Verification denied: show that completion could not be confirmed.
- Receipt write failed: show non-blocking warning after deletion report.

## Testing Strategy

Core tests:

- Safety scoring for bundle ID, full app name, updater folders, weak token matches, protected paths.
- Orphan scanner avoids unrelated packages with similar words.
- Orphan scanner groups bundle-id leftovers when no app bundle exists.
- Deletion verifier classifies deleted, remaining, missing, and permission-denied paths.
- App reset planner excludes app bundle and includes safe user state.
- Receipt store appends and reads records.
- Startup item parser reads LaunchAgent plist fixtures and classifies ownership.

App-support tests:

- App filters keep selection stable.
- Deletion report view model summarizes complete, partial, and failed results.
- Orphan files view model clears deleted groups only after verification.
- App reset mode changes confirmation and plan contents.

E2E/manual verification:

- Delete a disposable fixture app and confirm it disappears from the list.
- Confirm post-delete report shows verified removed paths.
- Confirm `DELETE` uninstalls and `RESET` resets without deleting the app bundle.
- Confirm Delete History shows the receipt.
- Confirm Orphan Files finds leftovers after manually removing only the app bundle.
- Confirm Startup Items screen can reveal and disable a disposable user LaunchAgent.

## Rollout Criteria

Milestone 1 is complete when:

- Deletion has path-level verification.
- Receipts are persisted.
- Delete History is functional.
- Orphan Finder can find and safely delete fixture leftovers.
- Candidate rows show safety and evidence.

Milestone 2 is complete when:

- Search, filters, and sorts work without stale selection bugs.
- App Reset deletes only related user state and keeps the app bundle.
- Reset has its own verification report and receipt.

Milestone 3 is complete when:

- Startup Items lists user/system startup entries.
- User LaunchAgents can be disabled and re-enabled.
- Destructive startup item deletion requires explicit confirmation.

## Open Implementation Risks

- macOS permissions may prevent complete scans. The UI must report incomplete coverage honestly.
- Last-opened metadata may be unavailable or unreliable for some apps.
- Startup item management can require administrator privileges for system locations.
- Broad name matching can produce false positives. Bundle-id and exact-name evidence should dominate selection defaults.
- Receipt history stores local paths. The app should provide a clear history deletion action.
