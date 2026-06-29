# Permission Policy Design

Date: 2026-06-28

## Goal

Move MyMacFinder from passive permission error guidance to an explicit macOS access model that works well for both the current personal non-sandbox build and future sandboxed builds.

## Current State

The app already detects whether it is sandboxed through `APP_SANDBOX_CONTAINER_ID` and shows permission-denied guidance through `PermissionGuidance`. Settings includes a small Privacy & Access section with the sandbox status and an Open Privacy Settings button.

The current implementation does not let users choose a folder from an open panel, does not persist security-scoped bookmarks, and does not show granted folders in Settings. Permission failures are therefore informational only: users can read the guidance, but MyMacFinder cannot recover by asking for explicit access to the blocked folder.

## Scope

This phase includes:

- User-selected folder access through `NSOpenPanel`.
- Security-scoped bookmark persistence for sandboxed builds.
- A granted-folder store that can list and remove saved folder grants.
- Permission-denied recovery that offers `Choose Folder...` when folder access can help.
- Settings UI for sandbox status, granted folders, remove, and reset.
- Non-sandbox personal build behavior that keeps direct filesystem access working without forcing bookmark grants.
- Tests for bookmark storage, sandbox/non-sandbox guidance, recovery state, and settings-facing granted folder models.
- Focused manual QA with generated fixture folders and the built `.app`.

This phase does not include:

- Developer ID signing, notarization, or public distribution packaging.
- Privileged helper tools or admin escalation for protected system paths.
- Fine-grained per-file capability prompts.
- TCC automation or changing macOS privacy settings programmatically.
- Network-volume-specific policy beyond normal user-selected folder access.

## Product Behavior

### Non-Sandbox Personal Builds

The current personal build remains unrestricted by default. Users can navigate normal local filesystem paths without first granting a bookmark. If macOS privacy controls deny access, the app shows guidance for Full Disk Access and Files and Folders settings.

The Settings Privacy & Access section must clearly say that the build is not sandboxed. It can still show granted folders if any exist, but it must not imply that bookmark grants are required for ordinary use.

### Sandboxed Builds

When the app runs sandboxed, user-selected folder access becomes the primary recovery path.

Users can choose a folder through an `NSOpenPanel` configured for directories only. When a folder is chosen, MyMacFinder creates a security-scoped bookmark, stores it, starts access, and navigates or retries the failed operation when appropriate.

Stored bookmarks are resolved at launch or when first needed. If a bookmark is stale, the app refreshes and saves the updated bookmark. If a bookmark cannot be resolved, Settings shows the grant as unavailable and the app asks the user to choose the folder again.

### Permission Recovery

When an operation fails with `ExplorerError.permissionDenied(path)`, the alert behavior depends on runtime policy:

- Sandboxed: primary action is `Choose Folder...`.
- Non-sandboxed: primary action is `Open Privacy Settings`.

For sandboxed builds, `Choose Folder...` opens the folder access panel. The initial directory should be the denied path when it is a folder, or the closest existing parent directory when the denied path is a file or missing. If the user cancels, the alert closes without changing filesystem state.

After a successful grant, the store retries only the safe recovery target:

- If the failure happened during navigation or refresh, retry loading that location.
- If the failure happened during a read-only inspector action, retry that action when the selected item still exists.
- Write operations are not automatically retried in this phase. The app records the grant and asks the user to run the command again. This avoids repeating destructive operations after an access prompt.

### Settings

Settings must include a Privacy & Access section with:

- Sandbox status: Sandboxed or Unrestricted.
- A short explanation of the active policy.
- `Choose Folder...` button.
- Granted folders list with path, availability state, and stale state when known.
- Remove button for each grant.
- Reset Granted Folders button.
- Open Privacy Settings button.

The granted-folder list must be usable when empty. Empty state text should explain that sandboxed builds need folder grants for locations outside the container, while unrestricted builds usually do not.

## Architecture

### SecurityScopedBookmarkStore

Create `Sources/MyMacFinder/Services/SecurityScopedBookmarkStore.swift`.

Responsibilities:

- Persist folder grants in `UserDefaults`.
- Store bookmark data, display path, creation date, and last successful resolution date.
- Load all grants as value models.
- Save a new or refreshed grant.
- Remove one grant by id.
- Remove all grants.

The store should not show UI and should not directly navigate panes. It is a persistence boundary.

### UserSelectedFolderAccessService

Create `Sources/MyMacFinder/Services/UserSelectedFolderAccessService.swift`.

Responsibilities:

- Present `NSOpenPanel` for directory selection.
- Create bookmarks with security-scope options when sandboxed.
- Resolve stored bookmarks and call `startAccessingSecurityScopedResource()`.
- Balance access with `stopAccessingSecurityScopedResource()`.
- Return typed results that the store can test without AppKit UI in unit tests.

The service should be protocol-backed so tests can inject a fake folder picker and fake bookmark resolver.

### Permission Guidance

Extend `PermissionGuidance` so it returns an explicit recovery action enum instead of only an optional button title.

Expected recovery actions:

- `chooseFolder`
- `openPrivacySettings`
- `none`

This keeps alert wiring testable and prevents string comparisons from driving behavior.

### ExplorerStore

`ExplorerStore` owns permission recovery state because it already owns navigation, refresh, active selection, and visible errors.

Add state for:

- The last permission-denied path.
- The safe retry target, such as navigation or refresh.
- Granted folder summaries for Settings.
- Async grant resolution status.

Store rules:

- Do not start security-scoped access for archive virtual URLs.
- Do not auto-retry write operations after a grant.
- Refresh visible panes after grants are added or removed.
- If a grant is removed and a visible pane no longer loads, show the normal permission guidance.

### Settings UI

Keep Settings in `MyMacFinderApp.swift` for this phase, matching the existing Settings structure. If the Privacy & Access section grows too large during implementation, split it into a small `PrivacyAccessSettingsView` under `Sources/MyMacFinder/UI/`.

Settings actions call store methods:

- `chooseFolderForAccess()`
- `removeGrantedFolder(id:)`
- `resetGrantedFolders()`
- `openPrivacySettings()`

## Data Flow

### Choose Folder From Settings

1. User opens Settings.
2. User clicks `Choose Folder...`.
3. Store asks `UserSelectedFolderAccessService` to present the folder picker.
4. Service returns a selected URL or cancellation.
5. Store saves the bookmark through `SecurityScopedBookmarkStore` when sandboxed.
6. Store starts access and refreshes granted-folder summaries.
7. Visible panes refresh if their paths are covered by the granted folder.

### Permission-Denied Navigation Recovery

1. User navigates to a folder.
2. File system read fails with `ExplorerError.permissionDenied(path)`.
3. Store records visible error and safe retry target.
4. Alert offers `Choose Folder...` in sandboxed builds.
5. User chooses a folder.
6. Store saves and starts access.
7. Store retries the original navigation.
8. If retry fails, the new error is shown normally.

### App Launch

1. Store initializes sandbox summary.
2. Store loads bookmark metadata for Settings display.
3. In sandboxed builds, bookmark access is started lazily when a path needs it or when Settings resolves grant availability.
4. Stale bookmarks are refreshed when successfully resolved.

## Error Handling

- User cancellation from `NSOpenPanel` is not an error.
- Bookmark creation failure shows a readable alert and leaves existing grants unchanged.
- Bookmark resolution failure marks that grant unavailable in Settings.
- Stale bookmark refresh failure leaves the old bookmark and shows a readable warning only when the user attempts to use that grant.
- Removing a grant stops active access if it was started by MyMacFinder.
- Resetting grants stops all active access started by MyMacFinder.
- Permission-denied alerts must include the path that failed.

## Testing

Automated tests must cover:

- Sandbox summary still distinguishes sandboxed and unrestricted environments.
- Permission guidance chooses `chooseFolder` for sandboxed permission errors.
- Permission guidance chooses `openPrivacySettings` for unrestricted permission errors.
- Bookmark store saves, loads, removes, and resets grants using an isolated `UserDefaults`.
- Bookmark store updates stale bookmark data after a refreshed resolution.
- User-selected folder service maps picker cancellation to a non-error result.
- ExplorerStore records a safe retry target for navigation permission failures.
- ExplorerStore does not auto-retry write commands after granting access.
- Settings-facing granted-folder summaries include path, availability, and stale status.

Manual QA must use `build/MyMacFinder.app` and generated fixture folders. It must cover:

- Non-sandbox build still opens normal folders without grants.
- Settings Privacy & Access shows Unrestricted for the personal build.
- `Choose Folder...` from Settings can add a folder grant record.
- Removing a grant updates the list.
- Reset clears the list.
- Permission-denied guidance still offers Open Privacy Settings in the personal build.

Sandbox-specific manual QA is only required when a sandboxed build script exists. If this phase adds such a script, QA must also cover sandboxed folder selection and bookmark recovery.

## Implementation Order

1. Add permission recovery domain types and extend `PermissionGuidance`.
2. Add `SecurityScopedBookmarkStore` and focused persistence tests.
3. Add `UserSelectedFolderAccessService` protocol and AppKit implementation.
4. Inject the access service and bookmark store into `ExplorerStore`.
5. Add store state for granted folders and permission recovery targets.
6. Wire alert recovery actions in `RootView`.
7. Expand Settings Privacy & Access UI.
8. Add manual QA document.
9. Run targeted tests, full `swift test`, `git diff --check`, `./scripts/build_app.sh`, and app manual QA.

## Acceptance Criteria

- Permission errors no longer only explain the problem; sandboxed builds can recover through `Choose Folder...`.
- Non-sandbox personal builds keep current direct-access behavior.
- Stored grants are visible and removable from Settings.
- Bookmark persistence and permission guidance are covered by unit tests.
- The built app passes focused manual QA before the phase is committed.

## Self-Review

- Spec coverage: every Phase 2 roadmap requirement is represented: `NSOpenPanel`, security-scoped bookmarks, recovery action, Settings granted locations, and non-sandbox behavior.
- Placeholder scan: no deferred placeholder tokens or undefined feature stubs remain.
- Scope check: this is one implementation phase. Signing, notarization, and network-volume-specific policy stay out of scope.
- Ambiguity check: write operations are explicitly not auto-retried after granting access.
