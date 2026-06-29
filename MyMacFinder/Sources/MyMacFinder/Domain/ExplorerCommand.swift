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
    case rename
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

    public var title: String {
        switch self {
        case .open: return "Open"
        case .openInTerminal: return "Open in Terminal"
        case .openInVSCode: return "Open in VS Code"
        case .chooseOpenWithApplication: return "Choose Application..."
        case .quickLook: return "Quick Look"
        case .revealInFinder: return "Reveal in Finder"
        case .copyPath: return "Copy Path"
        case .newFolder: return "New Folder"
        case .rename: return "Rename"
        case .duplicate: return "Duplicate"
        case .extractZip: return "Extract ZIP"
        case .compressToZip: return "Compress to ZIP"
        case .editTags: return "Edit Tags"
        case .undo: return "Undo"
        case .selectAll: return "Select All"
        case .addToFavorites: return "Add to Favorites"
        case .copy: return "Copy"
        case .cut: return "Cut"
        case .paste: return "Paste"
        case .moveToTrash: return "Move to Trash"
        case .calculateFolderSize: return "Calculate Size"
        case .refresh: return "Refresh"
        case .focusSearch: return "Focus Search"
        case .focusPath: return "Focus Path"
        case .clearSearch: return "Clear Search"
        case .toggleHiddenFiles: return "Toggle Hidden Files"
        case .toggleInspector: return "Toggle Inspector"
        case .goBack: return "Back"
        case .goForward: return "Forward"
        case .goUp: return "Go Up"
        case .newTab: return "New Tab"
        case .closeTab: return "Close Tab"
        case .nextTab: return "Next Tab"
        case .previousTab: return "Previous Tab"
        }
    }

    public var yieldsToTextEditing: Bool {
        switch self {
        case .undo, .selectAll, .copy, .cut, .paste:
            return true
        case .open, .openInTerminal, .openInVSCode, .chooseOpenWithApplication, .quickLook, .revealInFinder,
             .copyPath, .newFolder, .rename, .duplicate, .extractZip, .compressToZip, .editTags,
             .addToFavorites, .moveToTrash, .calculateFolderSize, .refresh,
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
            case .newFolder, .openInTerminal, .openInVSCode, .chooseOpenWithApplication, .rename, .duplicate,
                 .extractZip, .compressToZip, .editTags, .copy, .cut, .paste, .moveToTrash, .calculateFolderSize:
                return false
            case .addToFavorites:
                return false
            }
        }

        switch self {
        case .newFolder, .refresh, .focusSearch, .focusPath, .clearSearch, .toggleHiddenFiles, .toggleInspector, .selectAll:
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
        case .openInTerminal, .openInVSCode:
            return selectionCount == 1
                && selectedEntries.first?.isDirectoryLike == true
                && selectedEntries.first?.isArchiveBacked == false
        case .chooseOpenWithApplication:
            return selectionCount > 0
                && !selectedEntries.contains { $0.isArchiveBacked }
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
        case .open, .quickLook, .revealInFinder, .copyPath, .duplicate, .copy, .cut, .moveToTrash:
            return selectionCount > 0
        }
    }
}
