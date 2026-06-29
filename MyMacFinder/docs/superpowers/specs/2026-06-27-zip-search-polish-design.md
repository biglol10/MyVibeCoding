# ZIP Browsing, Search, Performance, Shortcuts, And QA Design Spec

Date: 2026-06-27

## Purpose

This spec closes the remaining v0.1 usability gaps for MyMacFinder after the file operations, synchronization, settings, sorting, drag/drop, and inspector work. The scope is intentionally practical: read-only ZIP browsing, current-folder search, large-folder performance verification, shortcut polish, and a full manual QA pass.

The goal is not to make MyMacFinder a full archive editor or Spotlight replacement. The goal is to make the current local file manager feel complete enough for daily use.

## Scope

Included:

- Read-only ZIP internal browsing.
- Current-pane search by name, extension, and kind.
- Native table performance verification for large folders.
- Shortcut and menu polish for high-frequency workflows.
- A manual QA checklist that is run against the actual app, not only scripts.

Excluded:

- Editing ZIP contents.
- Creating ZIP archives.
- Password-protected ZIP extraction.
- Copying or dragging ZIP internal items out as extraction.
- Global indexed search.
- Recursive content search.
- Background indexing daemons.

## ZIP Browsing

ZIP files are entered like folders. Double-clicking a `.zip` file opens a virtual location representing the archive root. The pane path changes to a readable archive path, such as:

```text
/Users/biglol/Downloads/sample.zip/
/Users/biglol/Downloads/sample.zip/docs/readme.txt
```

The table shows ZIP entries with familiar columns:

- Name
- Size
- Date Modified, when available from the archive
- Kind

Folders inside the ZIP can be opened. Back, Forward, Up, and Refresh work inside the virtual archive path. Hidden-file visibility applies to archive entries whose names begin with `.`.

ZIP internal items are read-only in v0.1. These commands are disabled inside archive locations:

- Delete
- Rename
- Move
- Paste into archive
- New Folder
- Drag/drop into archive

These commands remain available:

- Open extracted temporary copy for ZIP file entries
- Quick Look extracted temporary copy for ZIP file entries
- Copy Path as virtual archive path
- Reveal in Finder for the host ZIP file

Copying or dragging ZIP internal items out of the archive is not included in this pass. The first implementation focuses on internal browsing and preview stability.

Damaged, unsupported, or encrypted ZIP files show a clear error state and keep the pane at the previous valid location.

## Archive Architecture

Add an archive service boundary instead of mixing ZIP parsing into `ExplorerStore`.

Core types:

```swift
public struct ArchiveLocation: Equatable, Hashable, Sendable {
    public var archiveURL: URL
    public var internalPath: String
}

public struct ArchiveEntry: Equatable, Sendable {
    public var location: ArchiveLocation
    public var name: String
    public var isDirectory: Bool
    public var size: Int64?
    public var modifiedAt: Date?
}

public protocol ArchiveBrowsing {
    func canOpen(_ url: URL) -> Bool
    func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry]
    func temporaryExtract(_ location: ArchiveLocation) async throws -> URL
}
```

`ExplorerStore` keeps the current pane location as a small enum:

```swift
public enum PaneLocation: Equatable, Sendable {
    case fileSystem(URL)
    case archive(ArchiveLocation)
}
```

Regular filesystem panes continue to use `FileSystemService`. Archive panes use `ArchiveBrowsingService`. UI code receives displayable `FileEntry` values so the table does not need to know whether the row came from disk or a ZIP file.

## Search

Search is scoped to the active pane and filters the currently loaded entries. It is not recursive in this pass.

Search behavior:

- `Cmd+F` focuses the search field.
- Typing filters the active pane entries immediately.
- `Esc` clears search when the search field or table is focused.
- Search matches case-insensitively.
- Search checks filename, extension, and kind text.
- Sorting continues to apply to the filtered results.
- Selection clears if selected rows are filtered out.
- The inspector updates from the filtered table selection.

Search applies in both filesystem and archive panes. For archive entries, path search can match the visible internal entry name and kind, but not full recursive internal paths in this v0.1 pass.

The toolbar shows a compact native search field near the path controls. It does not replace the path field and does not change the current folder path.

## Large-Folder Performance

The app already uses an AppKit `NSTableView`, which gives native row virtualization. This pass validates and hardens that behavior.

Performance targets for a synthetic folder with 10,000 files:

- Initial listing completes without beachballing the app.
- Scrolling does not create all row views eagerly.
- Selecting rows stays responsive.
- Sorting by Name, Size, Date Modified, and Kind completes without a permanent UI freeze.
- Search filtering updates predictably and does not corrupt selection state.
- Inspector preview work runs only for current selection, not for every row.

Implementation avoids eager thumbnail generation, eager recursive folder-size calculation, and unnecessary full table rebuilds during selection-only updates.

If a 50,000-file test exposes a specific bottleneck, fix the bottleneck rather than adding speculative infrastructure.

## Shortcut And Menu Polish

The shortcut set prioritizes Finder/Explorer muscle memory without breaking text editing in the path field or search field.

Required shortcuts:

- `Cmd+L`: focus path field.
- `Cmd+F`: focus search field.
- `Esc`: clear search if active, otherwise cancel transient UI state.
- `Space`: Quick Look selected items.
- `Cmd+Shift+.`: toggle hidden files.
- `Cmd+R`: refresh.
- `Cmd+Up`: go to parent folder.
- `Return`: open selected item when table focus is active.
- `Cmd+Delete`: move selected filesystem items to Trash.

Shortcut behavior is tested at the command-routing layer when it maps to an `ExplorerCommand`. UI focus behavior must be manually verified in the running app because AppKit responder-chain details are hard to prove with unit tests alone.

The Explorer menu exposes the same commands, so keyboard shortcuts, menu commands, context menus, and inspector buttons share command routing.

## Manual QA

Manual QA must use a real `.app` bundle launched from the release build.

The QA pass covers:

- ZIP open, nested folder navigation, Up, Back, Forward, Refresh.
- ZIP damaged/encrypted error handling using at least one invalid `.zip`.
- Search in a normal folder.
- Search inside a ZIP folder.
- Clearing search with `Esc`.
- `Cmd+F`, `Cmd+L`, `Space`, `Cmd+Shift+.`, `Cmd+R`, and `Cmd+Up`.
- 10,000-file folder load, scroll, sort, search, selection, and inspector behavior.
- Existing file operations still work in normal filesystem panes.
- File mutation commands are disabled or safely rejected inside ZIP panes.
- Single pane, dual pane, and inspector-visible settings still work.
- External filesystem changes still refresh normal filesystem panes.

QA artifacts are created in temporary folders or clearly named home-directory folders and removed after testing.

## Testing Strategy

Automated tests cover:

- Archive path parsing and navigation.
- Listing ZIP root and nested folders.
- Hidden archive entry filtering.
- Damaged ZIP error propagation.
- Search filtering by name, extension, and kind.
- Search clearing and selection cleanup.
- Command availability inside archive locations.
- Shortcut mapping for new or polished shortcuts.

Manual tests cover:

- Actual AppKit focus behavior.
- Quick Look window presentation.
- Large-folder scrolling and perceived responsiveness.
- Visual correctness of search and archive paths.

## Acceptance Criteria

- Double-clicking a ZIP opens a read-only archive location.
- Normal pane navigation works inside ZIP folders.
- Search filters active pane entries in filesystem and archive locations.
- `Cmd+F`, `Esc`, and existing navigation shortcuts behave correctly in the running app.
- 10,000-file folder QA completes without app crash or unusable UI lag.
- File mutation commands are unavailable or rejected in ZIP locations.
- All automated tests pass.
- Full manual QA is run on the actual built app.
