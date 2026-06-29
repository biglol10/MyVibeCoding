# Regression Audit - 2026-06-29

## Goal

Analyze MyMacFinder feature clusters one by one, add missing edge-case coverage, and record evidence so regressions are easier to catch before manual use.

## Current Feature Map

Source of truth for this pass:

- README feature list
- `Tests/MyMacFinderTests`
- `docs/qa`
- Current Swift source under `Sources/MyMacFinder`

## Cluster 1: Sidebar, Favorites, Recent Folders, Path Focus

Reviewed files:

- `Sources/MyMacFinder/UI/SidebarView.swift`
- `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- `Sources/MyMacFinder/Domain/SidebarModels.swift`
- `Tests/MyMacFinderTests/ExplorerSidebarStoreTests.swift`
- `Tests/MyMacFinderTests/SidebarFavoritesStoreTests.swift`
- `Tests/MyMacFinderTests/ExplorerTabStoreTests.swift`
- `Tests/MyMacFinderTests/ExplorerSearchStoreTests.swift`
- `Tests/MyMacFinderTests/PathInputFieldTests.swift`
- `Tests/MyMacFinderTests/ExplorerStorePathInputCommandTests.swift`
- `Sources/MyMacFinder/Services/ExternalAppLauncher.swift`
- `Tests/MyMacFinderTests/ExternalAppLauncherTests.swift`

Existing verified coverage:

- Full-row sidebar hit targets for Favorites rows
- Favorites add from active folder and selected folder
- Duplicate prevention for newly added Favorites
- Missing Favorites render as disabled/secondary items
- Missing Recent Folder click removes the row without presenting an error
- Recent Folders are limited to five when recorded
- Sidebar and Recent navigation clear toolbar path focus
- Folder navigation clears active search
- Tab switching preserves independent search state
- Path input handles text editing shortcuts without routing them as file commands
- Path input commands route `cmd`, `terminal`, `code .`, and `open .` without navigating to fake relative paths

New edge cases found and covered:

- Stored Recent Folders could contain duplicates from older/corrupt defaults. This could waste the five visible Recent slots and show repeated rows. Added a failing test first, then normalized stored Recent Folders by standardized URL before trimming to five.
- Stored Favorites could contain duplicate URLs from older/corrupt defaults. This could show the same folder multiple times even though runtime add prevents duplicates. Added a failing test first, then normalized stored Favorites by standardized URL while preserving the first item.
- `cmd` / `terminal` used the same awaited `NSWorkspace.open` completion path as Open With. Terminal can report a completion error even after opening successfully, which should not become a MyMacFinder error or termination path. Added a failing test first, then made Terminal launches fire-and-forget after checking Terminal.app exists.
- A stale toolbar-focus flag could let the global shortcut monitor steal `Cmd+A/C/V` from the focused path text field. In manual use this could append `cmd` to the existing path instead of replacing it. Added a failing routing test first, then made the monitor also inspect the actual AppKit first responder before routing file commands.

Focused verification:

```bash
swift test --filter ExplorerSidebarStoreTests/testStoredRecentFoldersAreDeduplicatedBeforeTrimmingOnLoad
swift test --filter ExplorerSidebarStoreTests/testStoredFavoritesAreDeduplicatedByURLOnLoad
swift test --filter ExternalAppLauncherTests/testOpenTerminalDoesNotSurfaceWorkspaceCompletionErrors
swift test --filter ExplorerShortcutRoutingTests/testActualTextEditingFocusYieldsEditingShortcutsWhenToolbarFocusStateIsStale
swift test --filter 'ExplorerSidebarStoreTests|SidebarFavoritesStoreTests|ExplorerTabStoreTests|ExplorerSearchStoreTests|PathInputFieldTests|ExplorerStorePathInputCommandTests'
swift test --filter 'ExternalAppLauncherTests|ExplorerStorePathInputCommandTests|PathInputCommandResolverTests|FilePreviewThumbnailLoaderTests'
swift test --filter 'ExplorerStorePathInputCommandTests|PathInputCommandResolverTests|ExternalAppLauncherTests|ExplorerShortcutRoutingTests|FilePreviewThumbnailLoaderTests'
```

Focused result:

- 42 selected tests passed with 0 failures.
- Latest path-command focused run passed 23 selected tests with 0 failures.

## Remaining Clusters

Not yet re-audited in this pass:

- None in the current README feature map

## Cluster 2: File Operations, Conflict Handling, Undo

Reviewed files:

- `Sources/MyMacFinder/Services/FileOperationService.swift`
- `Sources/MyMacFinder/Services/FileOperationManifestBuilder.swift`
- `Sources/MyMacFinder/Domain/FileOperationResult.swift`
- `Sources/MyMacFinder/Domain/FileUndoAction.swift`
- `Sources/MyMacFinder/Domain/FileConflictModels.swift`
- `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- `Tests/MyMacFinderTests/FileOperationServiceTests.swift`
- `Tests/MyMacFinderTests/ExplorerStoreTests.swift`
- `Tests/MyMacFinderTests/ExplorerUndoCommandTests.swift`
- `Tests/MyMacFinderTests/ExplorerStoreDropTests.swift`
- `Tests/MyMacFinderTests/FileDropValidatorTests.swift`
- `Tests/MyMacFinderTests/FileClipboardTests.swift`
- `Tests/MyMacFinderTests/AppKitFileConflictResolverTests.swift`

Existing verified coverage:

- Create folder, rename, duplicate, copy, move, trash
- Same-folder copy uses `copy` naming and does not replace the source
- Same-folder move is a no-op
- Copy/move descendant guards
- Copy/move conflict decisions: Replace, Keep Both, Skip, Cancel
- Rename separator validation and rename replacement
- Clipboard copy/cut/paste command flow
- System pasteboard file URL paste fallback
- Drop copy/move and invalid descendant drop rejection
- Operation progress completed/failed auto-dismiss behavior
- Undo for create, rename, and move

New edge cases found and covered:

- Multi-item copy with a later missing source could copy earlier items, then throw a Cocoa error before the store could record undo. Added a failing test first, then preflighted all sources before copying.
- Multi-item move with a later missing source could move earlier items, then throw before undo was recorded. Added a failing test first, then preflighted all sources before moving.
- Multi-item trash with a later missing source could move earlier items to Trash, then throw before undo was recorded. Added a failing test first, then preflighted all sources before trashing.
- Copy with Replace could move the existing destination to Trash and then fail while copying the source, leaving the old destination missing with no undo action recorded. Added a failing test first, then rolled back replaced destinations when the write step fails.
- ZIP extraction with Replace could move an existing destination folder to Trash and then fail or cancel during extraction, leaving a partial extraction folder instead of the original folder. Added a failing test first, then rolled back replaced destinations and partial extraction output on failure.
- ZIP compression with Replace could move an existing archive to Trash and then fail while creating the replacement archive, leaving the old archive missing. Added a failing test first, then rolled back replaced archives on failure.
- Copy Replace undo ordering was explicitly covered: the copied replacement is removed before the old destination is restored, avoiding destination-exists failures during undo.

Focused verification:

```bash
swift test --filter 'FileOperationServiceTests/testCopyItemsPreflightsSourcesBeforeCopyingAnyItem|FileOperationServiceTests/testMoveItemsPreflightsSourcesBeforeMovingAnyItem|FileOperationServiceTests/testMoveToTrashPreflightsSourcesBeforeTrashingAnyItem'
swift test --filter FileOperationServiceTests/testCopyReplaceRestoresExistingDestinationWhenCopyFailsAfterTrash
swift test --filter ZipExtractionServiceTests/testReplaceRestoresExistingDestinationWhenExtractionIsCancelledAfterTrash
swift test --filter ZipCompressionServiceTests/testReplaceRestoresExistingArchiveWhenCompressionFailsAfterTrash
swift test --filter ExplorerUndoCommandTests/testUndoCopyReplaceRemovesCopiedItemBeforeRestoringReplacedDestination
swift test --filter 'FileOperationServiceTests|ExplorerStoreTests|ExplorerUndoCommandTests|ExplorerStoreDropTests|FileDropValidatorTests|FileClipboardTests|FileOperationManifestBuilderTests|FileOperationProgressReporterTests|FileOperationProgressTests|FileConflictModelTests|AppKitFileConflictResolverTests'
swift test --filter 'FileOperationServiceTests|ExplorerUndoCommandTests|ZipExtractionServiceTests|ZipCompressionServiceTests|ExplorerZipExtractionCommandTests|ExplorerZipCompressionCommandTests'
```

Focused result:

- 74 selected tests passed with 0 failures.
- Latest replace/ZIP/undo focused run passed 40 selected tests with 0 failures.

## Cluster 3: ZIP Browse, Preview Extraction, Compression, Extraction

Reviewed files:

- `Sources/MyMacFinder/Services/ArchiveBrowsingService.swift`
- `Sources/MyMacFinder/Services/ArchivePathSafety.swift`
- `Sources/MyMacFinder/Services/ZipExtractionService.swift`
- `Sources/MyMacFinder/Services/ZipCompressionService.swift`
- `Sources/MyMacFinder/Domain/ArchiveModels.swift`
- `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- `Tests/MyMacFinderTests/ArchiveBrowsingServiceTests.swift`
- `Tests/MyMacFinderTests/ArchiveModelsTests.swift`
- `Tests/MyMacFinderTests/ExplorerArchiveCommandTests.swift`
- `Tests/MyMacFinderTests/ExplorerArchiveNavigationTests.swift`
- `Tests/MyMacFinderTests/ExplorerZipCompressionCommandTests.swift`
- `Tests/MyMacFinderTests/ExplorerZipExtractionCommandTests.swift`
- `Tests/MyMacFinderTests/ZipCompressionServiceTests.swift`
- `Tests/MyMacFinderTests/ZipExtractionServiceTests.swift`

Existing verified coverage:

- ZIP files open as archive locations
- Archive root and nested folder listing
- Hidden archive entry filtering
- Temporary extraction for Quick Look / preview
- Invalid ZIP read failures produce readable errors
- ZIP extraction into named folders
- Extraction collision handling with Keep Both
- Extraction progress updates
- Invalid ZIP extraction does not create a folder or replace an existing destination
- ZIP compression for multiple items and single folder roots
- Compression destination collision handling with Keep Both
- Store commands record undo for ZIP extraction and compression
- Mutating file commands are disabled inside archive locations

New edge cases found and covered:

- Archive browsing showed unsafe entry path components such as `..`, absolute paths, and Windows drive-style roots as folders/files. Added a failing test first, then filtered unsafe archive entry paths from listing.
- Temporary extraction could preview an unsafe archive entry path if called directly. Added a failing test first, then rejected unsafe paths before extraction.
- ZIP extraction detected unsafe entry paths only after creating the extraction folder and possibly extracting earlier files. Added a failing test first, then validated all archive entry paths before creating the extraction folder.
- ZIP extraction with Replace could trash an existing destination folder before later detecting an unsafe entry path. Added a failing test first, then moved entry path validation before conflict resolution.

Focused verification:

```bash
swift test --filter 'ZipExtractionServiceTests/testUnsafeZipEntryDoesNotLeavePartialExtractionFolder|ZipExtractionServiceTests/testUnsafeZipEntryDoesNotReplaceExistingDestinationFolder|ArchiveBrowsingServiceTests/testListSkipsUnsafeArchiveEntryPaths|ArchiveBrowsingServiceTests/testTemporaryExtractRejectsUnsafeArchiveEntryPaths'
swift test --filter 'ArchiveBrowsingServiceTests|ArchiveModelsTests|ExplorerArchiveCommandTests|ExplorerArchiveNavigationTests|ExplorerZipCompressionCommandTests|ExplorerZipExtractionCommandTests|ZipCompressionServiceTests|ZipExtractionServiceTests'
```

Focused result:

- 32 selected tests passed with 0 failures.

## Cluster 4: Inspector Preview Responsiveness and Cancellation

Reviewed files:

- `Sources/MyMacFinder/UI/FilePreviewView.swift`
- `Sources/MyMacFinder/UI/FilePreviewContentLoader.swift`
- `Sources/MyMacFinder/UI/FilePreviewThumbnailLoader.swift`
- `Sources/MyMacFinder/UI/InspectorView.swift`
- `Sources/MyMacFinder/Domain/FilePreviewContent.swift`
- `Sources/MyMacFinder/Domain/InspectorModels.swift`
- `Tests/MyMacFinderTests/FilePreviewContentLoaderTests.swift`
- `Tests/MyMacFinderTests/FilePreviewThumbnailLoaderTests.swift`
- `Tests/MyMacFinderTests/InspectorModelsTests.swift`
- `Tests/MyMacFinderTests/InspectorViewWiringTests.swift`
- `Tests/MyMacFinderTests/ExplorerInspectorCommandTests.swift`

Existing verified coverage:

- Text preview loading for Markdown, logs, JSON, text-like names, and read failures
- Large text preview byte limiting at 16KB for responsive inspector rendering
- Text preview file reads run off the main thread when called from `MainActor`
- Binary payload fallback for text-like files
- Visual preview path for image-like files
- Thumbnail loader can run outside the main actor
- Inspector single-selection details, multi-selection summary, folder size display, and Quick Look command wiring

New edge case found and covered:

- Cancelling a stale preview task did not cancel the detached background text read. SwiftUI `.task(id:)` prevented stale UI assignment after the read returned, but the old read could keep consuming background work while the user selected another file. Added a failing test first, then wired cancellation from the caller task into the detached preview read task.

Focused verification:

```bash
swift test --filter FilePreviewContentLoaderTests/testCancellationPropagatesToBackgroundTextReadTask
swift test --filter 'FilePreviewContentLoaderTests|FilePreviewThumbnailLoaderTests|InspectorModelsTests|InspectorViewWiringTests|ExplorerInspectorCommandTests'
```

Focused result:

- 20 selected tests passed with 0 failures.

## Cluster 5: Drag and Drop Pasteboard Behavior

Reviewed files:

- `Sources/MyMacFinder/UI/FileTableView.swift`
- `Sources/MyMacFinder/Services/FileDropPasteboardReader.swift`
- `Sources/MyMacFinder/Services/FileDropValidator.swift`
- `Sources/MyMacFinder/Domain/FileDropModels.swift`
- `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- `Tests/MyMacFinderTests/FileTableViewReuseTests.swift`
- `Tests/MyMacFinderTests/FileDropPasteboardReaderTests.swift`
- `Tests/MyMacFinderTests/FileDropValidatorTests.swift`
- `Tests/MyMacFinderTests/FileDropModelTests.swift`
- `Tests/MyMacFinderTests/ExplorerStoreDropTests.swift`

Existing verified coverage:

- Modern file URL pasteboard reads
- Legacy Finder `NSFilenamesPboardType` reads
- Accepted drag types include modern and legacy Finder file URL formats
- Local drops default to move; external drops default to copy
- Option-modified drops force copy
- External move proposals are ignored in favor of copy
- Empty drops, non-directory destinations, self-drops, and descendant copy/move drops are rejected
- Store-level drop copy and move flows refresh the table and preserve source/destination expectations
- File table context/menu bridge remains wired while drag/drop support is present

New edge case found and covered:

- Multi-row drag pasteboard writing did not apply the archive-backed guard used by single-row drag. This allowed ZIP virtual entries to be exported as `__MyMacFinderArchive__` file URLs and cleared the existing pasteboard. Added a failing test first, then skipped archive-backed entries before writing drag pasteboard data.

Focused verification:

```bash
swift test --filter FileTableViewReuseTests/testArchiveBackedRowsAreNotWrittenToDragPasteboard
swift test --filter 'FileDropPasteboardReaderTests|FileDropValidatorTests|FileDropModelTests|ExplorerStoreDropTests|FileTableViewReuseTests'
```

Focused result:

- 31 selected tests passed with 0 failures.

## Cluster 6: Finder Tags Read, Edit, Search, and Fallbacks

Reviewed files:

- `Sources/MyMacFinder/Services/FinderTagService.swift`
- `Sources/MyMacFinder/Services/FileSystemService.swift`
- `Sources/MyMacFinder/Services/FileSearchService.swift`
- `Sources/MyMacFinder/Domain/FinderTag.swift`
- `Sources/MyMacFinder/Domain/FileEntrySearchFilter.swift`
- `Sources/MyMacFinder/Domain/InspectorModels.swift`
- `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- `Sources/MyMacFinder/UI/FileTableView.swift`
- `Sources/MyMacFinder/UI/InspectorView.swift`
- `Tests/MyMacFinderTests/FinderTagServiceTests.swift`
- `Tests/MyMacFinderTests/FinderTagTests.swift`
- `Tests/MyMacFinderTests/FileSystemServiceTests.swift`
- `Tests/MyMacFinderTests/FileEntrySearchFilterTests.swift`
- `Tests/MyMacFinderTests/FileSearchServiceTests.swift`
- `Tests/MyMacFinderTests/ExplorerFinderTagCommandTests.swift`
- `Tests/MyMacFinderTests/ExplorerAdvancedSearchStoreTests.swift`
- `Tests/MyMacFinderTests/ExplorerSearchStoreTests.swift`
- `Tests/MyMacFinderTests/InspectorModelsTests.swift`
- `Tests/MyMacFinderTests/FileTableViewReuseTests.swift`
- `Tests/MyMacFinderTests/ExplorerArchiveCommandTests.swift`
- `Tests/MyMacFinderTests/ExplorerCommandTests.swift`

Existing verified coverage:

- Finder tags read/write through macOS resource values
- Empty tag lists clear Finder tags
- Tag normalization trims, sorts, and deduplicates case-insensitively
- Directory listing can include Finder tags when requested
- Directory listing skips tag reads when tag metadata is not needed
- Finder tag read failures fallback to empty tags so unsupported volumes do not break basic listing
- Table and inspector render Finder tag text
- General search and advanced tag filter match Finder tag names
- Current-folder and recursive tag filters load tag metadata when needed
- Edit Tags writes prompted tags, refreshes the table, and preserves selection when the item remains visible
- Edit Tags cancellation leaves tags and selection unchanged
- ZIP-backed virtual entries do not expose Edit Tags

New edge case found and covered:

- Editing a selected file's tags while an active tag filter was showing that file could leave the now-hidden file internally selected after the edited tags no longer matched the filter. Added a failing test first, then trimmed selection to the current visible entries after tag edits.

Focused verification:

```bash
swift test --filter ExplorerFinderTagCommandTests/testEditTagsClearsSelectionWhenEditedTagsNoLongerMatchActiveTagFilter
swift test --filter 'FinderTagServiceTests|FinderTagTests|FileSystemServiceTests|FileEntrySearchFilterTests|ExplorerFinderTagCommandTests|ExplorerAdvancedSearchStoreTests|ExplorerSearchStoreTests|FileSearchServiceTests|InspectorModelsTests|FileTableViewReuseTests|ExplorerArchiveCommandTests|ExplorerCommandTests'
```

Focused result:

- 65 selected tests passed with 0 failures.

## Cluster 7: Table View Rendering, Column Sizing, Selection, Shortcuts, and Context Menus

Reviewed files:

- `Sources/MyMacFinder/UI/FileTableView.swift`
- `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
- `Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift`
- `Sources/MyMacFinder/App/RootView.swift`
- `Tests/MyMacFinderTests/FileTableViewReuseTests.swift`
- `Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift`
- `Tests/MyMacFinderTests/ExplorerShortcutRoutingTests.swift`
- `Tests/MyMacFinderTests/ExplorerCommandTests.swift`
- `Tests/MyMacFinderTests/ExplorerArchiveCommandTests.swift`
- `Tests/MyMacFinderTests/ExplorerInspectorCommandTests.swift`

Existing verified coverage:

- Reusable table cells keep stable per-column identifiers
- Name cells render icons; text-only columns do not inherit icons from reused cells
- Archive-backed rows use fallback icons and are not exported to drag pasteboard as real file URLs
- Long column text clips inside cell bounds instead of overflowing adjacent columns
- Date Modified uses compact timestamps to fit narrow panes
- Tags column renders Finder Tags text
- Regular columns fit dual-pane minimum width while keeping Date Modified readable
- Table columns apply readable minimum widths and allow user/autoresizing
- Last column receives remaining width in narrow dual-pane layouts
- Item context menu includes Open With and routes application choices
- Empty and item context menus share ExplorerCommand enablement
- Right-clicking an unselected row selects it before building the item menu
- Table focus publishes even when selection does not change
- Standard responder actions route Copy, Cut, Paste, Select All, and Undo through the table when available
- Keyboard shortcut mappings and toolbar text-input routing are covered separately from AppKit responder actions

New edge case found and covered:

- The Tags table column exposed an AppKit sort descriptor even though `SortKey` and `SortEngine` do not support tag sorting. This made the header look sortable while clicking it could not change the store sort. Added a failing test first, then limited table sort descriptors to columns backed by real store sort keys.

Focused verification:

```bash
swift test --filter FileTableViewReuseTests/testOnlySupportedColumnsExposeSortDescriptors
swift test --filter 'FileTableViewReuseTests|ExplorerKeyboardShortcutTests|ExplorerShortcutRoutingTests|ExplorerCommandTests|ExplorerArchiveCommandTests|ExplorerInspectorCommandTests'
```

Focused result:

- 42 selected tests passed with 0 failures.

## Cluster 8: Settings, Pane Mode, Inspector Visibility, Hidden Files, and Default Sort

Reviewed files:

- `Sources/MyMacFinder/Services/ExplorerSettingsStore.swift`
- `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- `Tests/MyMacFinderTests/ExplorerLayoutSettingsTests.swift`
- `Tests/MyMacFinderTests/ExplorerSettingsStoreTests.swift`
- `Tests/MyMacFinderTests/ExplorerSortSettingsTests.swift`
- `Tests/MyMacFinderTests/ExplorerTabStoreTests.swift`
- `Tests/MyMacFinderTests/ExplorerFocusCommandTests.swift`
- `Tests/MyMacFinderTests/ExplorerShortcutRoutingTests.swift`

Existing verified coverage:

- Default layout starts as single pane with inspector visible
- Persisted pane mode, inspector visibility, hidden-file preference, and default sort load on startup
- Switching to dual pane creates and loads a second pane at the active folder
- Switching back to single pane keeps the active pane
- Show Hidden Files refreshes the current listing immediately
- Default Sort persists and resorts visible panes
- Tab switching preserves independent navigation and search state
- Focus commands and hidden-file shortcuts route through the store

New edge case found and covered:

- Changing Default Sort only updated currently visible panes. Inactive tabs kept their previous pane sort state, so switching back to another tab could restore an old sort even though Settings showed the new default. Added a failing test first, then applied the new descriptor to panes in all open tabs.

Focused verification:

```bash
swift test --filter ExplorerSortSettingsTests/testSettingDefaultSortUpdatesInactiveTabs
swift test --filter 'ExplorerLayoutSettingsTests|ExplorerSettingsStoreTests|ExplorerSortSettingsTests|ExplorerTabStoreTests|ExplorerFocusCommandTests|ExplorerShortcutRoutingTests'
```

Focused result:

- 30 selected tests passed with 0 failures.

## Cluster 9: Directory Watcher Synchronization and External File Changes

Reviewed files:

- `Sources/MyMacFinder/Services/DirectoryWatcherService.swift`
- `Sources/MyMacFinder/Services/FileSystemService.swift`
- `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- `Sources/MyMacFinder/Domain/ArchiveModels.swift`
- `Tests/MyMacFinderTests/ExplorerStoreWatcherTests.swift`
- `Tests/MyMacFinderTests/FileSystemServiceTests.swift`
- `Tests/MyMacFinderTests/ExplorerArchiveNavigationTests.swift`
- `Tests/MyMacFinderTests/ArchiveBrowsingServiceTests.swift`
- `Tests/MyMacFinderTests/ExplorerSearchStoreTests.swift`
- `Tests/MyMacFinderTests/ExplorerAdvancedSearchStoreTests.swift`

Existing verified coverage:

- Initial directory load starts a watcher
- Filesystem navigation restarts the watcher for the new folder
- External file creation refreshes the active pane without manual Refresh
- Dual-pane mode refreshes an inactive visible pane when its folder changes
- Folder symlinks are directory-like and can be listed through their target
- Current-folder and recursive search refresh paths keep search state and selection coherent
- Archive navigation, nested archive folders, and archive root Up behavior are covered

New edge case found and covered:

- ZIP archive panes did not watch the host ZIP file location. When the user was inside a ZIP and another app replaced or modified that ZIP, the virtual archive listing could stay stale until navigation or manual Refresh. Added a failing test first, then made archive panes watch the host ZIP's parent directory and reload archive panes on matching watcher events.

Focused verification:

```bash
swift test --filter ExplorerStoreWatcherTests/testWatcherChangeRefreshesOpenArchiveWhenHostZipChanges
swift test --filter 'ExplorerStoreWatcherTests|FileSystemServiceTests|ExplorerArchiveNavigationTests|ArchiveBrowsingServiceTests|ExplorerSearchStoreTests|ExplorerAdvancedSearchStoreTests'
```

Focused result:

- 34 selected tests passed with 0 failures.

## Cluster 10: Permission Recovery and Sandboxed Folder Grants

Reviewed files:

- `Sources/MyMacFinder/Domain/PermissionGuidance.swift`
- `Sources/MyMacFinder/Domain/FolderAccessGrant.swift`
- `Sources/MyMacFinder/Services/SecurityScopedBookmarkStore.swift`
- `Sources/MyMacFinder/Services/UserSelectedFolderAccessService.swift`
- `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- `Tests/MyMacFinderTests/PermissionGuidanceTests.swift`
- `Tests/MyMacFinderTests/SecurityScopedBookmarkStoreTests.swift`
- `Tests/MyMacFinderTests/UserSelectedFolderAccessServiceTests.swift`
- `Tests/MyMacFinderTests/ExplorerPermissionRecoveryTests.swift`
- `docs/qa/permission-policy-manual-qa.md`

Existing verified coverage:

- Sandboxed permission errors offer `Choose Folder...`; unrestricted builds point to macOS Privacy settings
- Permission-denied navigation records the denied path for safe retry
- Alert dismissal does not lose the captured retry path when the caller passes it back
- Folder picker cancellation leaves stored grants unchanged
- Chosen folders are saved as grants and shown in Settings-facing summaries
- Removing and resetting grants updates the list
- Bookmark store saves, loads, replaces by URL, removes, and resets grants
- User-selected folder service creates bookmark data only for sandboxed builds and starts access for sandboxed selections

New edge cases found and covered:

- Sandboxed app startup loaded persisted folder grants only as static summaries. It did not resolve stored security-scoped bookmarks or start access, so a grant could appear in Settings after relaunch while still not authorizing filesystem access. Added failing tests first, then resolved persisted grants during sandboxed store initialization and published availability/stale state.
- Unresolvable persisted bookmarks stayed in an ambiguous `unknown` state. Added a failing test first, then marked those grants unavailable in Settings-facing summaries.
- Re-selecting a folder that already had a persisted grant replaced the stored grant by URL but did not stop the superseded active security-scoped access. Added a failing test first, then stopped and removed matching active access before saving the replacement grant.

Focused verification:

```bash
swift test --filter 'ExplorerPermissionRecoveryTests/testSandboxedInitResolvesPersistedGrantsAndPublishesAvailability|ExplorerPermissionRecoveryTests/testSandboxedInitMarksUnresolvablePersistedGrantsUnavailable'
swift test --filter ExplorerPermissionRecoveryTests/testChoosingExistingGrantedFolderStopsSupersededAccess
swift test --filter 'ExplorerPermissionRecoveryTests|PermissionGuidanceTests|SecurityScopedBookmarkStoreTests|UserSelectedFolderAccessServiceTests'
```

Focused result:

- 20 selected permission tests passed with 0 failures.

## Cluster 11: Mounted Volumes and Network Locations

Reviewed files:

- `Sources/MyMacFinder/Services/VolumeService.swift`
- `Sources/MyMacFinder/Domain/MountedVolume.swift`
- `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- `Sources/MyMacFinder/UI/SidebarView.swift`
- `Tests/MyMacFinderTests/MountedVolumeTests.swift`
- `Tests/MyMacFinderTests/ExplorerVolumeStoreTests.swift`
- `Tests/MyMacFinderTests/ExplorerSidebarStoreTests.swift`

Existing verified coverage:

- Mounted volumes are loaded from `FileManager.mountedVolumeURLs`
- Hidden/non-browsable volumes are skipped by the volume service
- Network, removable, and local volumes get distinct sidebar icons
- Sidebar sorting puts network volumes before removable and local volumes
- Volume refresh failures are surfaced as readable sidebar errors

New edge cases found and covered:

- A mounted volume row can become stale after an external unmount or network disconnect. Clicking it previously attempted normal navigation and left the stale row in Locations. Added a failing test first, then made Locations clicks remove missing mounted volumes and store a readable path error.
- A mounted volume can still exist but be reported as unreadable. Clicking it should not move the active pane into a broken path. Added a failing test first, then blocked navigation and surfaced a permission error while keeping the mounted row visible for retry/refresh.

Focused verification:

```bash
swift test --filter ExplorerVolumeStoreTests
swift test --filter 'ExplorerVolumeStoreTests|MountedVolumeTests|ExplorerSidebarStoreTests'
```

Focused result:

- 24 selected mounted-volume/sidebar tests passed with 0 failures.

## Cluster 12: App Bundle, Icon, Signing, Personal Package

Reviewed files:

- `scripts/create-app-bundle.sh`
- `scripts/build_app.sh`
- `scripts/verify-app-icon.sh`
- `scripts/package_personal.sh`
- `Sources/MyMacFinder/Resources/AppIcon.icns`
- `Sources/MyMacFinder/Resources/AppIcon.iconset`
- `README.md`

Existing verified coverage:

- `create-app-bundle.sh` builds the SwiftPM executable, creates `.build/app/MyMacFinder.app`, copies `AppIcon.icns`, writes `Info.plist`, and marks the executable bit
- `build_app.sh` copies the internal app to `build/MyMacFinder.app`, clears extended attributes, applies local ad-hoc signing, verifies the signature, and registers the bundle with Launch Services when available
- `verify-app-icon.sh` validates preview/iconset PNG dimensions, expands the `.icns`, builds a debug app bundle, and verifies `CFBundleIconFile`
- `package_personal.sh` builds the release app, signs the packaged app, creates `Install MyMacFinder.command`, writes `README-FIRST.txt`, creates a zip, and runs `unzip -tq`

New edge cases found:

- No code-level gap was found in this pass. The remaining risk is operational rather than unit-testable: public distribution still needs Developer ID signing, notarization, and auto-update, which README already lists as a known limitation.

Focused verification:

```bash
./scripts/build_app.sh
./scripts/verify-app-icon.sh
./scripts/package_personal.sh
unzip -l dist/MyMacFinder-personal-mac.zip
codesign --verify --deep --strict --verbose=2 build/MyMacFinder.app
codesign --verify --deep --strict --verbose=2 dist/MyMacFinder-personal-mac/MyMacFinder.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' dist/MyMacFinder-personal-mac/MyMacFinder.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' dist/MyMacFinder-personal-mac/MyMacFinder.app/Contents/Info.plist
test -x 'dist/MyMacFinder-personal-mac/Install MyMacFinder.command'
```

Focused result:

- App bundle build passed and produced `build/MyMacFinder.app`
- App icon verification passed
- Personal package zip was created at `dist/MyMacFinder-personal-mac.zip`
- The package zip contained the app bundle, `Install MyMacFinder.command`, and `README-FIRST.txt`
- Both `build/MyMacFinder.app` and packaged `dist/MyMacFinder-personal-mac/MyMacFinder.app` passed strict codesign verification
- Packaged app `Info.plist` reported `CFBundleExecutable=MyMacFinder` and `CFBundleIconFile=AppIcon`
