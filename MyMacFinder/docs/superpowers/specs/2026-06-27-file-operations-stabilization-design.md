# File Operations Stabilization Design

## Goal

Stabilize destructive and write-heavy file workflows before adding broader product features. This phase adds explicit collision handling, undo support, ZIP extraction, and a repeatable long manual QA checklist.

## Scope

This phase includes:

- Conflict handling for copy, move, paste, duplicate, rename, drag-and-drop, and ZIP extraction destinations.
- Undo support for create folder, rename, duplicate, copy, move, paste, drag-and-drop file operations, move to trash, and ZIP extraction.
- ZIP extraction from selected `.zip` files into the current folder or a chosen destination.
- A longer manual QA script with fixture generation and observable expected results.

This phase does not include:

- Tabs.
- Advanced search.
- App sandboxing/signing/notarization.
- Network volume-specific behavior.
- Editing ZIP contents in place.

Those items are separate phases that begin only after the shared write-operation foundation is stable.

## Product Behavior

### Collision Handling

When an operation would write an item to a destination path that already exists, MyMacFinder must show a decision UI before writing:

- **Replace**: overwrite the destination item.
- **Keep Both**: create a unique name using the existing local naming style.
- **Skip**: skip this item and continue the remaining batch.
- **Cancel**: stop the whole operation before further writes.

For a single-item operation, **Skip** behaves like a no-op. For a batch operation, **Skip** applies only to the current item.

Rename collisions show a narrower dialog:

- **Replace**: replace the existing destination.
- **Keep Both**: rename to a unique name derived from the requested name.
- **Cancel**: keep the original item unchanged.

Directory replace must be conservative: replacing a folder means moving the destination folder to Trash first, then moving/copying the new folder into place. If the trash step fails, the operation must stop without deleting source data.

### Undo

Undo is command-based and LIFO. Each successful write operation records an undo action:

- Create folder: move created folder to Trash.
- Rename: move the renamed item back to its original URL.
- Duplicate/copy/paste copy/drag copy: move created copies to Trash.
- Move/paste move/drag move: move items back from destination to original URLs.
- Move to Trash: restore items from the trash result URLs when possible.
- ZIP extraction: move extracted files/folders to Trash.

Undo must be exposed through:

- `Cmd+Z` in the file table.
- Menu command.
- Context menu item when an undo action exists.

If undo cannot complete because a path is missing or occupied, show a readable error and keep the failed undo action available only when retrying is safe. For partial undo failures, already reverted items remain reverted and the error lists the first failed item.

### ZIP Extraction

When one or more ZIP files are selected, the context menu and menu bar offer **Extract ZIP**.

Default behavior:

- Extract into the active pane's current file-system folder.
- Create a destination folder named after each ZIP file without `.zip`.
- If that folder already exists, use the same collision dialog.
- Extracted content must preserve directory structure.

ZIP extraction is not available inside archive browsing mode. It applies to real file-system ZIP files only.

### Long Manual QA

Add a manual QA checklist that can be executed after automated tests. It covers:

- Collision decisions for copy, move, rename, duplicate, drag-and-drop, and ZIP extraction.
- Undo after each write operation.
- Batch copy/move with Skip and Cancel.
- Folder replacement with Trash fallback.
- ZIP extraction with nested files and collisions.
- Existing file-operation regressions: create, delete, copy, cut, paste, rename, drag-and-drop, external sync.
- Large-folder smoke check using the existing fixture script.

The checklist must include fixture setup commands, exact UI actions, expected filesystem results, and cleanup commands.

## Architecture

### File Operation Layer

Introduce explicit operation planning before writing:

- `FileConflictPolicy` describes a user decision: replace, keep both, skip, or cancel.
- `FileConflict` describes source URL, proposed destination URL, and operation kind.
- `FileConflictResolving` asks the UI for a decision.
- `FileOperationResult` reports created, moved, trashed, skipped, and failed URLs.

`FileOperationService` becomes the single place that applies collision policy and records enough information for undo. It does not show AppKit UI directly.

### Store Layer

`ExplorerStore` coordinates UI commands and file operations:

- It injects a conflict resolver.
- It records undo actions after successful operations.
- It exposes `canUndo` and an undo command.
- It refreshes panes after write operations and after undo.
- It keeps archive locations read-only except for extracting host ZIP files from file-system panes.

### UI Layer

Add a small AppKit-backed conflict dialog service used by the store:

- Single-item dialog shows item name, destination folder, operation, and buttons.
- Batch dialog includes current item and count context, such as `3 of 12`.
- The dialog does not permanently block state updates beyond the active operation.

Add menu/context-menu entries for:

- Undo.
- Extract ZIP.

Keyboard shortcut:

- `Cmd+Z` maps to undo.

## Data Flow

1. User starts a write operation from menu, context menu, shortcut, paste, or drag-and-drop.
2. `ExplorerStore` validates whether the active location supports the operation.
3. Store calls `FileOperationService`.
4. Service computes destination paths.
5. If a collision exists, service asks `FileConflictResolving` for a decision.
6. Service applies the operation according to the decision.
7. Service returns `FileOperationResult`.
8. Store records undo action when the result changed the filesystem.
9. Store refreshes panes and updates selection.
10. If user invokes Undo, store executes the newest undo action through the same service-level primitives, then refreshes.

## Error Handling

- User cancellation is not an error and does not show an alert.
- Permission errors must show the path and operation name.
- Archive extraction errors must identify the ZIP file path.
- Batch operations continue after **Skip** but stop after **Cancel** or unrecoverable filesystem errors.
- Partial operation results must still be represented so undo can clean up successful writes.

## Testing

Automated tests must cover:

- Collision decisions for copy, move, rename, duplicate, and extraction.
- Batch skip and cancel behavior.
- Undo action creation for each supported operation.
- Undo execution for create, rename, copy, move, trash, and extract.
- Command availability for Undo and Extract ZIP.
- Keyboard mapping for `Cmd+Z`.
- Archive browsing remains read-only.

Manual QA must be run against a generated `.app` bundle after automated tests pass.

## Implementation Order

1. Add collision model and resolver protocol.
2. Refactor `FileOperationService` to accept collision decisions and return operation results.
3. Add undo model and undo stack in `ExplorerStore`.
4. Wire Undo command, shortcut, menu, and context menu.
5. Add ZIP extraction service and command.
6. Add AppKit conflict dialogs.
7. Add long manual QA document and fixture scripts.
8. Run automated tests, release build, app icon verification, and manual QA.
