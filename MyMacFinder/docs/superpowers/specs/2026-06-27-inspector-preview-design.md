# Inspector Preview Design Spec

Date: 2026-06-27

## Goal

Upgrade the right inspector from a basic path panel into a daily-use ForkLift-style file context panel. The inspector should make selected files understandable and actionable without forcing the user to leave the file list.

This pass intentionally combines action buttons, richer metadata, multi-selection summaries, folder size calculation, and first-pass preview support.

## Scope

This pass includes:

- Single-selection inspector details:
  - Preview area
  - File or folder name
  - Kind
  - Extension
  - Size
  - Date created
  - Date modified
  - Date accessed, when available
  - Full path
  - Hidden status
  - Readable status
- Single-selection actions:
  - Open
  - Quick Look
  - Reveal in Finder
  - Copy Path
  - Calculate Size for folders
- Multi-selection inspector details:
  - Selection count
  - File count
  - Folder count
  - Known total size for non-folder files
  - Common parent folder when all selected items share one parent
  - A compact list of the first selected names
- Preview behavior:
  - Use a native macOS preview surface for selected file thumbnails where possible.
  - Fall back to the real macOS file icon when a rich preview is unavailable.
  - Keep preview generation asynchronous so selecting a large file or folder does not block the file list.
- Quick Look behavior:
  - Inspector button and keyboard command use the same command routing.
  - Quick Look opens for selected files and folders through the system Quick Look panel.
- Manual QA with the launched app:
  - Image file
  - Text or document file
  - PDF if available
  - Folder
  - Multiple selection
  - No selection

This pass does not include:

- Editing metadata.
- Open With menus.
- Recursive folder size calculation by default.
- ZIP virtual-entry previews.
- Custom media playback controls.
- Search result inspector behavior.

## Architecture

### Inspector Data Model

Add a small, testable inspector model layer instead of putting formatting and summary logic directly inside `InspectorView`.

Suggested types:

```swift
public struct InspectorItemDetails: Equatable {
    public var name: String
    public var kind: String
    public var fileExtension: String
    public var sizeText: String
    public var dateCreatedText: String
    public var dateModifiedText: String
    public var dateAccessedText: String
    public var path: String
    public var isHiddenText: String
    public var isReadableText: String
    public var isDirectoryLike: Bool
}

public struct InspectorSelectionSummary: Equatable {
    public var itemCount: Int
    public var fileCount: Int
    public var folderCount: Int
    public var knownTotalSizeText: String
    public var commonParentPath: String?
    public var previewNames: [String]
}
```

The exact names can change during implementation, but the boundary should remain: view rendering consumes prepared details, and tests cover the model/formatter behavior.

### Store And Commands

Extend the shared command layer so inspector actions do not create a separate action path.

New commands:

- `quickLook`
- `calculateFolderSize`

Existing commands reused:

- `open`
- `revealInFinder`
- `copyPath`

`ExplorerStore` remains responsible for operations with side effects:

- Open selected item.
- Reveal selected item in Finder.
- Copy selected path.
- Start Quick Look for the current selection.
- Calculate folder size only when the user explicitly requests it.

Folder size calculation should not run automatically. It can be expensive and should be user-triggered from the inspector. The result should appear in inspector state without changing the filesystem.

### Preview Surface

Use AppKit where native macOS behavior is needed.

Implementation direction:

- Create an `NSViewRepresentable` preview view.
- Prefer `QLThumbnailGenerator` for thumbnails where possible.
- Fall back to `NSWorkspace.shared.icon(forFile:)`.
- Cancel or ignore stale preview work when selection changes.
- Keep fixed preview dimensions so UI layout does not jump while previews load.

The preview area is not a decorative card. It is an inspector tool surface: compact, stable, and useful.

### UI Layout

The inspector should be vertically organized:

1. Preview area.
2. Primary file/folder name.
3. Action row.
4. Details grid.
5. Multi-selection summary when multiple items are selected.

Action controls should use native buttons with SF Symbol icons where appropriate:

- Open
- Quick Look
- Reveal
- Copy Path
- Calculate Size

Long paths and long names must wrap or truncate predictably. They must not overlap controls.

### Error Handling

- If Quick Look cannot open, show the existing `visibleError` alert path.
- If folder size calculation fails due to permissions or unreadable descendants, show a clear error using the existing alert path.
- If preview generation fails, show the file icon fallback instead of an alert.
- If no item is selected, show the existing no-selection state with improved spacing.

## Testing Strategy

Automated tests:

- Single item detail formatting:
  - Missing extension displays `--`.
  - Missing dates display `--`.
  - Size formatting uses file-style byte formatting.
  - Hidden/readable booleans display stable labels.
- Multi-selection summary:
  - Correct file and folder counts.
  - Known file sizes are summed.
  - Folder sizes are not recursively calculated.
  - Common parent is shown only when all items share one parent.
- Command routing:
  - Quick Look requires at least one selected item.
  - Calculate Size requires exactly one selected folder.
  - Inspector actions call the same `ExplorerCommand` route as menus and shortcuts.
- Folder size service:
  - Computes recursive folder size only when called.
  - Handles nested files.
  - Surfaces unreadable path errors through existing error types.

Manual QA:

- Launch the app bundle, not only `swift test`.
- Select an image and confirm a visual preview or correct file icon appears.
- Select a PDF or document and confirm preview fallback behavior is stable.
- Select a normal file and test Open, Quick Look, Reveal, Copy Path.
- Select a folder and confirm size is not calculated until pressing Calculate Size.
- Press Calculate Size and confirm the size appears.
- Select multiple items and confirm summary counts and total known file size.
- Confirm inspector layout remains stable in single-pane and dual-pane modes.

## Acceptance Criteria

- Inspector shows useful previews or native file icons for selected entries.
- Inspector exposes Open, Quick Look, Reveal in Finder, Copy Path, and folder size calculation.
- Folder size is explicit and never automatic.
- Multi-selection summary is accurate and compact.
- Inspector actions reuse shared command routing.
- Automated tests cover formatter, summary, command availability, and folder size behavior.
- Release build succeeds.
- Manual QA is performed and recorded before implementation is considered complete.
