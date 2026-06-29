# MyMacFinder Sync And Drag Drop Design Spec

Date: 2026-06-27

## Goal

Add two Finder-baseline behaviors to MyMacFinder:

- Automatically refresh the active folder when files are created, deleted, moved, or renamed by another app.
- Support native file drag and drop for moving and copying files into the current folder or into visible folder rows.

This work builds on the existing command and file operation layer. It must not introduce a separate filesystem mutation path.

## Scope

This pass includes:

- Watch the active pane's current folder for external filesystem changes.
- Debounce change events before refreshing the active pane.
- Refresh selection safely after external changes.
- Drag selected rows from the file table as file URLs.
- Drop files onto empty table space to copy or move them into the current folder.
- Drop files onto folder rows to copy or move them into that folder.
- Accept drops from Finder and other apps that provide file URLs.
- Treat Option-drag as copy and normal same-app drag as move.
- Treat external Finder drops as copy by default unless the system drag operation explicitly requests move.
- Reuse existing collision behavior from `FileOperationService`.
- Surface failures through the existing `ExplorerStore.visibleError` alert path.
- Manual QA in the launched app after automated tests.

This pass does not include:

- Sidebar drag and drop.
- Dragging into breadcrumb/path components.
- Spring-loaded folders.
- Cross-pane drag and drop, because dual-pane UI is not implemented yet.
- Custom drag preview artwork.
- Recursive home-wide watching.
- Background indexing or Spotlight-style search refresh.

## Architecture

### Directory Watching

Create a focused `DirectoryWatcherService` that watches one directory URL at a time. The service owns the platform-specific event source and exposes a small callback API:

```swift
public final class DirectoryWatcherService {
    public func startWatching(_ url: URL, onChange: @escaping @Sendable () -> Void)
    public func stopWatching()
}
```

The watcher uses `FSEvents` for real app behavior. The active pane is the only watched location in this pass. When the user navigates, `ExplorerStore` stops the old watcher and starts a new watcher for the new current folder.

The watcher should coalesce rapid events. `ExplorerStore` also applies a short refresh debounce, so a batch copy does not cause repeated table reloads. A debounce window around 250ms is enough for UI responsiveness without causing churn.

### Store Integration

`ExplorerStore` remains the owner of pane state and refresh behavior.

New responsibilities:

- Start the watcher after initial directory load.
- Restart the watcher after successful navigation.
- Stop or replace the watcher when active folder changes.
- Expose a testable drop API:

```swift
public enum DropOperation {
    case copy
    case move
}

public func performDrop(
    urls: [URL],
    destinationFolder: URL,
    operation: DropOperation
) async
```

The drop API delegates to `FileOperationService.copyItems` or `FileOperationService.moveItems`, then refreshes the active pane. This keeps context menus, shortcuts, paste, and drag/drop using the same filesystem rules.

### Drag And Drop UI

`FileTableView` already wraps `NSTableView`, which is the correct place to add AppKit drag/drop behavior.

The table view will:

- Register for file URL pasteboard types.
- Write selected file URLs to the pasteboard during a drag.
- Validate drops over empty table area and folder rows.
- Reject drops over files that are not folders.
- Reject invalid self drops, such as moving an item into itself.
- Resolve the destination folder:
  - Empty table area: `activePane.currentURL`
  - Folder row: that row's folder URL
- Resolve the operation:
  - Option key present: copy
  - Same-app drag without Option: move
  - External drag: copy unless AppKit provides a move operation

The SwiftUI wrapper should receive a closure rather than performing file operations directly:

```swift
var onDropItems: ([URL], URL, DropOperation) -> Void
```

`RootView` forwards this closure to `ExplorerStore.performDrop`.

## Safety Rules

Drag/drop must avoid destructive or nonsensical operations:

- Moving a file or folder into itself is ignored.
- Moving a folder into one of its descendants is rejected.
- Dropping onto a non-folder row is rejected.
- Empty URL drops are rejected.
- Destination collisions reuse `FileOperationService` naming rules.
- Failed operations set `visibleError` and do not partially mutate UI state beyond the filesystem result.

The current app does not implement undo, so this pass must avoid direct delete semantics. Move operations are normal filesystem moves, not trash operations.

## Event Refresh Behavior

The active folder should refresh when external changes occur:

- New file appears.
- Existing file disappears.
- File is renamed.
- File metadata changes enough for `FSEvents` to report a folder-level event.

Refresh should preserve valid selection where possible. If a selected file is deleted or moved away, the selection is removed by the existing intersection logic.

The path input must not be overwritten while the user is editing a different path. This pass will not add a full path-bar editing-state model. It will keep automatic refresh isolated to file entries and selection so watcher-driven refreshes do not introduce new path input overwrites.

## Testing Strategy

Automated tests:

- `DirectoryWatcherService` can be unit-tested through a testable scheduler/debounce helper rather than relying entirely on real `FSEvents` timing.
- `ExplorerStore` tests cover external refresh by invoking the same watcher callback path or an explicit `handleDirectoryChangedForTesting` method.
- `ExplorerStore.performDrop` tests cover copy into current folder, move into folder row destination, collision naming, and invalid self/descendant drops.
- `FileOperationService` tests remain the source of truth for copy/move collision behavior.
- Drag operation mapping should be tested with a pure helper so modifier handling is not buried inside AppKit-only delegate methods.

Manual QA:

- Launch the app as a `.app` bundle so Accessibility can inspect it.
- Navigate to a temporary QA folder.
- Create a file from Terminal and confirm it appears without pressing Refresh.
- Delete or rename a file from Terminal and confirm the table updates.
- Drag a file from Finder into empty table space and confirm copy.
- Drag an app row onto a folder row and confirm move.
- Option-drag a file onto a folder row and confirm copy.
- Try dropping a folder into itself or a descendant and confirm the app rejects it without changing files.

## Acceptance Criteria

- Current folder updates automatically after external create/delete/rename.
- File table accepts Finder file drops.
- File table supports row drag from MyMacFinder.
- Empty-area drop copies or moves into the current folder.
- Folder-row drop copies or moves into that folder.
- Invalid drops are rejected.
- Existing copy/move collision naming still works.
- All automated tests pass.
- Release build succeeds.
- Manual QA is performed and recorded in the final report.
