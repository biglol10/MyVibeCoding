# MyMacFinder Design Spec

Date: 2026-06-27

## Product Definition

MyMacFinder is a macOS-native file manager for users who want Windows Explorer style path navigation without giving up Finder-level file management basics. It is not a web app wrapped as a desktop app. It should feel like a real Mac app, while making direct path input, developer folders, advanced sorting, and inspector-based file context more efficient than Finder.

The product goal for v0.1 is:

> A daily-usable macOS file manager with Finder baseline behavior, a Windows-style address bar, ForkLift-style inspector, configurable dual-pane support, robust sorting/grouping, ZIP read-only browsing, and automatic synchronization with external filesystem changes.

## Non-Goals

v0.1 will not include:

- FTP, SFTP, or remote server file transfer.
- Direct cloud provider integration beyond normal local filesystem paths.
- Git dashboards, package script execution, or developer project analytics.
- Editing files inside ZIP archives.
- Privileged admin escalation for protected paths.
- Global Spotlight-grade indexing.

These are deferred because v0.1 must first be a trustworthy local file manager.

## Technology Direction

The app will use a SwiftUI + AppKit hybrid architecture.

- SwiftUI owns the app shell, window composition, toolbar, sidebar, inspector, settings, and high-level state bindings.
- AppKit is used where macOS file-manager quality matters: table/list behavior, multi-selection, drag and drop, keyboard navigation, Quick Look integration, file icons, context menus, and Finder-compatible workspace actions.
- System frameworks include `FileManager`, `NSWorkspace`, `QuickLook`, `UniformTypeIdentifiers`, `FSEvents`, and AppKit menu/shortcut APIs.

External UI libraries are not a primary design tool. The UI should use Apple-native controls, SF Symbols, native materials, system menus, and macOS Human Interface Guidelines.

## Main Window

The default layout is:

- Sidebar
- Toolbar and path address bar
- Main file table
- Right inspector panel

The main toolbar focuses on file navigation and high-frequency actions:

- Back
- Forward
- Up
- Path input
- Search
- Refresh
- Settings

Single/dual pane and inspector visibility are not exposed as persistent toolbar toggles. They are controlled from Settings and menu commands.

## Settings Window

The app includes a dedicated Settings window with these sections:

- Layout
- Sidebar
- Path and aliases
- View, sorting, and grouping
- Apps
- Shortcuts
- File operations

Settings include:

- Default view mode: single pane or dual pane
- Show inspector
- Remember window layout
- Sidebar sections and favorites
- Path aliases
- Default sort and group mode
- Hidden file visibility
- Column visibility
- Keymap: Windows-style, Finder-style, custom
- Default terminal app
- Default editor app
- File operation confirmation behavior

## Pane Model

The internal state model supports one or more panes from the start. v0.1 opens in single-pane mode by default, but dual-pane mode is available from Settings.

```swift
struct ExplorerState {
    var panes: [PaneState]
    var activePaneID: PaneID
    var sidebar: SidebarState
    var settings: UserSettings
}

struct PaneState {
    var id: PaneID
    var currentURL: URL
    var entries: [FileEntry]
    var selectedURLs: Set<URL>
    var backStack: [URL]
    var forwardStack: [URL]
    var sort: SortDescriptor
    var group: GroupDescriptor?
    var isLoading: Bool
    var error: ExplorerError?
}
```

This avoids rewriting navigation, selection, and file operations when dual-pane mode is enabled.

## File List

The file list must support:

- List/table view
- Multi-selection
- Keyboard navigation
- Inline rename
- Column sorting
- Grouped display
- Drag and drop
- Context menus
- Large folder virtualization

The preferred implementation is an AppKit `NSTableView` bridge, because it is better suited than a pure SwiftUI table for large folder performance, multi-selection, keyboard behavior, context menus, and drag and drop.

Virtualization is required. The app must not render every row eagerly for folders with thousands or tens of thousands of entries. Directory loading, metadata loading, sorting, and grouping must not block the main UI.

## Sorting And Grouping

v0.1 includes broad sorting and grouping support.

Sort keys:

- Name
- Size
- Kind
- Extension
- Date modified
- Date created
- Date last opened/accessed, when available
- Permissions
- Owner/group, when available
- Finder tags for normal filesystem entries
- Hidden status
- Folder/file type
- Path, especially for search results and ZIP browsing

Sort direction:

- Ascending
- Descending

Folder/file ordering:

- Folders first
- Files first
- Mixed

Group keys:

- None
- Folder/file
- Kind
- Extension
- Date buckets
- Size buckets
- Finder tags for normal filesystem entries
- Regular filesystem versus ZIP virtual entries

Sorting and grouping preferences are saved. The app can remember them globally and, if enabled, per folder. ZIP virtual entries do not expose Finder tags in v0.1, so tag sorting/grouping is unavailable inside ZIP browsing.

## Hidden Files

Hidden file visibility is user-controlled.

- Toolbar or View menu toggle
- Shortcut: `Cmd + Shift + .`
- Settings default
- Optional per-folder memory

Hidden criteria:

- Names beginning with `.`
- macOS hidden file flags

When hidden files are visible, they should be visually distinguishable with a subtle muted style. ZIP browsing applies the same hidden visibility rules where possible.

## Path Navigation

The path input is a core product feature.

Requirements:

- Shows the current path
- Focus shortcut: `Cmd + L`
- Click/focus supports editing and copying the full path
- `Enter` or configured key submits the path
- Supports `~`
- Supports absolute paths
- Supports aliases such as `@home`, `@desktop`, `@downloads`, `@dev`, and user-defined aliases
- Shows errors without navigating away when the path is invalid
- Does not overwrite user text while the user is editing, even if filesystem refreshes occur

Navigation commands:

- Back
- Forward
- Parent directory
- Refresh
- Open folder
- Open in new pane, when dual mode is enabled

## Sidebar

Sidebar sections:

- Favorites
- Recent folders
- Devices/volumes
- Developer aliases

Default locations:

- Home
- Desktop
- Documents
- Downloads
- Applications
- Pictures
- iCloud Drive, when available

Favorites can be added, removed, renamed, and reordered. Recent folders are automatically recorded, deduplicated, and capped.

## Inspector

The right inspector is part of v0.1.

It displays:

- Preview
- File or folder name
- Kind
- Size
- Date modified
- Full path or virtual ZIP path
- Selection summary for multiple selected items

Actions:

- Copy Path
- Quick Look
- Reveal in Finder
- Open

For selected folders, the inspector can show basic metadata without automatically calculating expensive recursive folder size. Folder size calculation is user-triggered.

## Context Menus

Context menus are required for both empty space and selected items.

Empty-space context menu:

- New Folder
- Paste
- Sort By
- Group By
- Show Hidden Files
- Refresh
- Open in Terminal, if configured
- View Options
- Settings

File/folder context menu:

- Open
- Open With
- Quick Look
- Reveal in Finder
- Copy Path
- Copy
- Cut
- Paste, where valid
- Duplicate
- Rename
- Move to Trash
- Compress
- Add to Favorites, for folders
- Open in New Pane, for folders when dual pane is enabled
- Get Info or Show Inspector

These menus must call the same command system used by the menu bar, shortcuts, toolbar, and inspector buttons.

## Command System And Shortcuts

All actions are routed through a shared command layer.

Example command model:

```swift
enum ExplorerCommand {
    case open
    case openWith
    case quickLook
    case revealInFinder
    case copyPath
    case newFolder
    case rename
    case duplicate
    case copy
    case cut
    case paste
    case moveToTrash
    case compress
    case refresh
    case showHiddenFiles
    case sort(SortKey)
    case group(GroupKey?)
}
```

Baseline shortcuts:

- `Cmd + L`: focus path input
- `Enter`: open selected item in Windows-style keymap
- `Return`: rename in Finder-style keymap
- `Space`: Quick Look
- `Cmd + Up`: parent directory
- `Cmd + [`: back
- `Cmd + ]`: forward
- `Cmd + R`: refresh
- `Cmd + Shift + .`: show hidden files
- `Cmd + C`: copy
- `Cmd + X`: cut
- `Cmd + V`: paste
- `Cmd + Delete`: move to trash
- `Cmd + D`: duplicate
- `Cmd + I`: inspector/get info
- `Cmd + ,`: settings
- `Cmd + F`: search
- `Cmd + A`: select all

The app provides Windows-style, Finder-style, and custom keymaps.

## File Operations

v0.1 includes Finder-baseline file operations:

- New folder
- Rename
- Copy
- Move
- Duplicate
- Move to Trash
- Compress
- Decompress/open ZIP
- Drag and drop
- Clipboard copy/cut/paste

Safety policies:

- Delete means Move to Trash by default, not permanent deletion.
- Copy/move operations show progress.
- Long operations can be cancelled where possible.
- Conflicts show options: Replace, Keep Both, Skip, Apply to All.
- Rename is inline.
- Extension changes can show a warning depending on settings.
- New folder enters rename state immediately after creation.
- Same-volume drag defaults to move.
- Different-volume drag defaults to copy.
- Finder-compatible modifier keys are followed where possible.
- Finder clipboard compatibility is considered for file URLs.

Privileged admin escalation is excluded from v0.1.

## ZIP Browsing

v0.1 supports read-only ZIP browsing.

Behavior:

- Double-click a ZIP file to enter it as a virtual folder.
- Show ZIP contents in the file table.
- Allow preview, Quick Look where possible, and metadata display.
- Copying or dragging a ZIP internal item outside extracts it.
- ZIP internal items cannot be deleted, renamed, moved, or modified in v0.1.
- Damaged or encrypted ZIP files show a readable error state.

ZIP creation and modifying archive contents are deferred.

## Search

v0.1 includes local search for the current folder.

Requirements:

- Search by filename
- Search by extension
- Search by kind
- Optional recursive search
- Search results preserve useful columns and path display
- Search works with the same sorting/grouping system

Global indexed search is deferred.

## Filesystem Synchronization

External changes must be reflected automatically.

Use `FSEvents` to watch:

- Current folder for each open pane
- Relevant parent paths when needed
- Mounted/unmounted volumes
- ZIP files currently opened as virtual folders

Behavior:

- If Finder, Terminal, editor, or another app creates, deletes, renames, or modifies files, the current view refreshes.
- Events are debounced/throttled to avoid repeated expensive rescans.
- App-initiated operations and external changes are merged without flicker.
- If a selected item is deleted externally, selection is cleared and inspector shows a missing state.
- If a selected item is renamed externally and can be matched, selection is preserved.
- If the current folder is deleted, the app navigates to a valid parent or Home with a clear message.
- If a ZIP file changes externally, its virtual folder view refreshes.
- If an external disk is unmounted, panes pointing inside it recover gracefully.

The path field is not overwritten while the user is actively editing it.

## Local Storage

All user data is local.

Suggested paths:

- `~/Library/Application Support/MyMacFinder/settings.json`
- `~/Library/Application Support/MyMacFinder/state.json`
- `~/Library/Caches/MyMacFinder/`

Storage format:

- Codable JSON
- Versioned schema
- Load at startup
- Save when settings/state changes
- Back up and regenerate defaults if corrupted

Stored data:

- Favorites
- Recent folders
- Aliases
- Default view mode
- Inspector visibility
- Window size and panel widths
- Last paths
- Sort and group settings
- Hidden file visibility
- Columns
- Keymap
- Terminal/editor app preferences
- File operation confirmations
- Per-folder settings, if enabled

## Error Handling

Errors should be clear and non-destructive.

Cases:

- Invalid path input
- Permission denied
- Missing path
- Broken symlink
- External disk removed
- iCloud placeholder or unavailable item
- Copy/move/rename conflict
- Trash operation failure
- ZIP damaged or encrypted
- Large folder loading failure
- Settings file corruption

The app should preserve the current valid state when navigation fails.

## Testing Requirements

Automated tests and command-line builds are not enough to accept a feature. Every feature plan must include a manual QA pass where the app is launched and exercised through the real macOS UI.

Manual QA rules:

- Launch the app with `swift run MyMacFinder` or the packaged app.
- Test through the visible UI, not only unit tests or service-level scripts.
- Use real folders such as Home, Desktop, Downloads, Applications, and a temporary test folder.
- Verify mouse, keyboard, context menu, toolbar, sidebar, inspector, and Settings behavior when relevant.
- Verify Finder/Terminal/external-app interactions when the feature touches filesystem state.
- Record any UI issues, crashes, stale state, selection problems, or macOS permission prompts before marking the feature complete.
- Do not mark a feature complete if it only passed automated tests but was not manually exercised in the running app.

Path tests:

- `~/Downloads`
- `/Applications`
- Invalid path
- Permission-denied path
- Alias path

File list tests:

- Empty folder
- Folder with thousands of files
- Hidden files
- Symlinks
- External volume paths

File operation tests:

- New folder
- Rename
- Copy
- Move
- Duplicate
- Move to Trash
- Conflict handling
- Drag and drop
- Compress/decompress

Inspector tests:

- Image file
- Text file
- Folder
- ZIP internal item
- No selection
- Multiple selection

Menu and shortcut tests:

- Empty-space context menu
- Item context menu
- Windows-style keymap
- Finder-style keymap
- Menu bar command routing

ZIP tests:

- Normal ZIP browse
- Large ZIP
- Damaged ZIP
- Encrypted ZIP
- Copy ZIP internal item outside

Sync tests:

- External create
- External delete
- External rename
- External modify
- Current folder deleted
- Volume unmounted
- ZIP modified externally

Settings tests:

- Restart restores layout
- Settings file corruption recovers
- Sort/group/hidden state persists
- Keymap changes apply

## Acceptance Criteria

v0.1 is successful when:

- The app can be used as a normal local file manager for daily work.
- Direct path input is faster and more visible than Finder's path navigation.
- Finder-baseline file operations work safely.
- Sorting, grouping, hidden files, context menus, and shortcuts feel complete enough for real use.
- Large folders remain responsive through virtualization and async work.
- External file changes stay synchronized.
- Inspector provides useful preview, metadata, and path actions.
- ZIP files can be browsed read-only and extracted by copying items out.
- Settings survive restarts and recover from corruption.
