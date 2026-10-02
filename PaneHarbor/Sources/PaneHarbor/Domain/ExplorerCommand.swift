import Foundation

public enum ExplorerCommand: String, CaseIterable, Identifiable {
    case open
    case openInTerminal
    case openInVSCode
    case chooseOpenWithApplication
    case quickLook
    case revealInFinder
    case copyPath
    case newFolder
    case newFile
    case rename
    case batchRename
    case share
    case duplicate
    case extractZip
    case compressToZip
    case editTags
    case undo
    case selectAll
    case addToFavorites
    case copy
    case cut
    case paste
    case copyToOppositePane
    case moveToOppositePane
    case moveToTrash
    case calculateFolderSize
    case refresh
    case focusSearch
    case focusPath
    case clearSearch
    case toggleHiddenFiles
    case toggleInspector
    case goBack
    case goForward
    case goUp
    case newTab
    case closeTab
    case nextTab
    case previousTab

    public var id: String { rawValue }

    /// File writes share one progress/cancellation owner and undo journal.
    public var mutatesFileSystem: Bool {
        switch self {
        case .newFolder, .newFile, .rename, .batchRename, .duplicate, .extractZip,
             .compressToZip, .editTags, .undo, .paste, .copyToOppositePane,
             .moveToOppositePane, .moveToTrash:
            return true
        default:
            return false
        }
    }

    public var title: String {
        switch self {
        case .open: return L10n.text("Open")
        case .openInTerminal: return L10n.text("Open in Terminal")
        case .openInVSCode: return L10n.text("Open in VS Code")
        case .chooseOpenWithApplication: return L10n.text("Choose Application...")
        case .quickLook: return L10n.text("Quick Look")
        case .revealInFinder: return L10n.text("Reveal in Finder")
        case .copyPath: return L10n.text("Copy Path")
        case .newFolder: return L10n.text("New Folder")
        case .newFile: return L10n.text("New File")
        case .rename: return L10n.text("Rename")
        case .batchRename: return L10n.text("Batch Rename…")
        case .share: return L10n.text("Share…")
        case .duplicate: return L10n.text("Duplicate")
        case .extractZip: return L10n.text("Extract ZIP")
        case .compressToZip: return L10n.text("Compress to ZIP")
        case .editTags: return L10n.text("Edit Tags")
        case .undo: return L10n.text("Undo")
        case .selectAll: return L10n.text("Select All")
        case .addToFavorites: return L10n.text("Add to Favorites")
        case .copy: return L10n.text("Copy")
        case .cut: return L10n.text("Cut")
        case .paste: return L10n.text("Paste")
        case .copyToOppositePane: return L10n.text("Copy to Other Pane")
        case .moveToOppositePane: return L10n.text("Move to Other Pane")
        case .moveToTrash: return L10n.text("Move to Trash")
        case .calculateFolderSize: return L10n.text("Calculate Size")
        case .refresh: return L10n.text("Refresh")
        case .focusSearch: return L10n.text("Focus Search")
        case .focusPath: return L10n.text("Focus Path")
        case .clearSearch: return L10n.text("Clear Search")
        case .toggleHiddenFiles: return L10n.text("Toggle Hidden Files")
        case .toggleInspector: return L10n.text("Toggle Inspector")
        case .goBack: return L10n.text("Back")
        case .goForward: return L10n.text("Forward")
        case .goUp: return L10n.text("Go Up")
        case .newTab: return L10n.text("New Tab")
        case .closeTab: return L10n.text("Close Tab")
        case .nextTab: return L10n.text("Next Tab")
        case .previousTab: return L10n.text("Previous Tab")
        }
    }

    public var yieldsToTextEditing: Bool {
        switch self {
        case .undo, .selectAll, .copy, .cut, .paste:
            return true
        case .open, .openInTerminal, .openInVSCode, .chooseOpenWithApplication, .quickLook, .revealInFinder,
             .copyPath, .newFolder, .newFile, .batchRename, .share, .rename, .duplicate, .extractZip, .compressToZip, .editTags,
             .addToFavorites, .copyToOppositePane, .moveToOppositePane, .moveToTrash, .calculateFolderSize, .refresh,
             .focusSearch, .focusPath, .clearSearch, .toggleHiddenFiles, .toggleInspector, .goBack, .goForward,
             .goUp, .newTab, .closeTab, .nextTab, .previousTab:
            return false
        }
    }

    public func isEnabled(selectionCount: Int, canPaste: Bool) -> Bool {
        isEnabled(selectionCount: selectionCount, canPaste: canPaste, selectedEntries: [])
    }

    public func isEnabled(selectionCount: Int, canPaste: Bool, selectedEntries: [FileEntry]) -> Bool {
        isEnabled(
            selectionCount: selectionCount,
            canPaste: canPaste,
            selectedEntries: selectedEntries,
            isArchiveLocation: false
        )
    }

    public func isEnabled(
        selectionCount: Int,
        canPaste: Bool,
        selectedEntries: [FileEntry],
        isArchiveLocation: Bool
    ) -> Bool {
        isEnabled(
            selectionCount: selectionCount,
            canPaste: canPaste,
            canUndo: false,
            canCloseTab: false,
            selectedEntries: selectedEntries,
            isArchiveLocation: isArchiveLocation
        )
    }

    public func isEnabled(
        selectionCount: Int,
        canPaste: Bool,
        canUndo: Bool,
        canCloseTab: Bool = false,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        canGoUp: Bool = true,
        selectedEntries: [FileEntry],
        isArchiveLocation: Bool
    ) -> Bool {
        if isArchiveLocation {
            switch self {
            case .open, .quickLook, .revealInFinder, .copyPath:
                return selectionCount > 0
            case .undo:
                return canUndo
            case .newTab, .nextTab, .previousTab:
                return true
            case .closeTab:
                return canCloseTab
            case .goBack:
                return canGoBack
            case .goForward:
                return canGoForward
            case .goUp:
                return canGoUp
            case .refresh, .focusSearch, .focusPath, .clearSearch, .toggleHiddenFiles, .toggleInspector, .selectAll:
                return true
            case .newFolder, .newFile, .openInTerminal, .openInVSCode, .chooseOpenWithApplication, .batchRename, .share, .rename, .duplicate,
                 .extractZip, .compressToZip, .editTags, .copy, .cut, .paste,
                 .copyToOppositePane, .moveToOppositePane, .moveToTrash, .calculateFolderSize:
                return false
            case .addToFavorites:
                return false
            }
        }

        switch self {
        case .newFolder, .newFile, .refresh, .focusSearch, .focusPath, .clearSearch, .toggleHiddenFiles, .toggleInspector, .selectAll:
            return true
        case .goUp:
            return canGoUp
        case .goBack:
            return canGoBack
        case .goForward:
            return canGoForward
        case .newTab, .nextTab, .previousTab:
            return true
        case .closeTab:
            return canCloseTab
        case .undo:
            return canUndo
        case .paste:
            return canPaste
        case .openInTerminal:
            return selectionCount == 0 || (
                selectionCount == 1
                && selectedEntries.first?.isDirectoryLike == true
                && selectedEntries.first?.isArchiveBacked == false
            )
        case .openInVSCode:
            return selectionCount == 1
                && selectedEntries.first?.isDirectoryLike == true
                && selectedEntries.first?.isArchiveBacked == false
        case .chooseOpenWithApplication:
            return selectionCount > 0
                && !selectedEntries.contains { $0.isArchiveBacked }
        case .batchRename, .share:
            return selectionCount > 0 && !selectedEntries.contains { $0.isArchiveBacked }
        case .rename:
            return selectionCount == 1
        case .addToFavorites:
            return selectionCount == 1
                && selectedEntries.first?.isDirectoryLike == true
                && selectedEntries.first?.isArchiveBacked == false
        case .calculateFolderSize:
            return selectionCount == 1 && selectedEntries.first?.isDirectoryLike == true
        case .extractZip:
            return selectedEntries.contains { entry in
                !entry.isArchiveBacked && entry.fileExtension.localizedCaseInsensitiveCompare("zip") == .orderedSame
            }
        case .compressToZip:
            return selectionCount > 0 && selectedEntries.allSatisfy { !$0.isArchiveBacked }
        case .editTags:
            return selectionCount == 1 && selectedEntries.first?.isArchiveBacked != true
        case .open, .quickLook, .revealInFinder, .copyPath, .duplicate, .copy, .cut,
             .copyToOppositePane, .moveToOppositePane, .moveToTrash:
            return selectionCount > 0
        }
    }
}
