import Foundation

public enum ExplorerShortcutModifier: Hashable, Sendable {
    case command
    case control
    case option
    case shift
}

public struct ExplorerShortcut: Equatable, Sendable {
    public var key: String
    public var modifiers: Set<ExplorerShortcutModifier>

    public init(key: String, modifiers: Set<ExplorerShortcutModifier>) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }
}

public enum ExplorerKeyboardShortcut {
    public static func command(for shortcut: ExplorerShortcut) -> ExplorerCommand? {
        switch shortcut.modifiers {
        case [.command]:
            switch shortcut.key {
            case "a": return .selectAll
            case "c": return .copy
            case "x": return .cut
            case "v": return .paste
            case "d": return .duplicate
            case "f": return .focusSearch
            case "i": return .toggleInspector
            case "l": return .focusPath
            case "o": return .open
            case "r": return .refresh
            case "t": return .newTab
            case "w": return .closeTab
            case "z": return .undo
            case "left": return .goBack
            case "right": return .goForward
            case "up": return .goUp
            case "down": return .open
            case "delete": return .moveToTrash
            default: return nil
            }
        case [.command, .shift]:
            switch shortcut.key {
            case "n": return .newFolder
            case ".": return .toggleHiddenFiles
            default: return nil
            }
        case [.command, .option]:
            switch shortcut.key {
            case "c": return .copyPath
            case "r": return .revealInFinder
            default: return nil
            }
        case []:
            switch shortcut.key {
            case "f2":
                return .rename
            case "return":
                return .open
            case "space":
                return .quickLook
            case "escape":
                return .clearSearch
            default:
                return nil
            }
        case [.control]:
            switch shortcut.key {
            case "tab": return .nextTab
            default: return nil
            }
        case [.control, .shift]:
            switch shortcut.key {
            case "tab": return .previousTab
            default: return nil
            }
        default:
            return nil
        }
    }
}

public enum ExplorerShortcutRouting {
    public static func command(
        for shortcut: ExplorerShortcut,
        isToolbarTextInputFocused: Bool,
        isCommandEnabled: (ExplorerCommand) -> Bool
    ) -> ExplorerCommand? {
        command(
            for: shortcut,
            isToolbarTextInputFocused: isToolbarTextInputFocused,
            isTextEditingResponderFocused: false,
            isCommandEnabled: isCommandEnabled
        )
    }

    public static func command(
        for shortcut: ExplorerShortcut,
        isToolbarTextInputFocused: Bool,
        isTextEditingResponderFocused: Bool,
        isCommandEnabled: (ExplorerCommand) -> Bool
    ) -> ExplorerCommand? {
        let isModifiedAppShortcut = shortcut.modifiers.contains(.command) || shortcut.modifiers.contains(.control)
        let isUnmodifiedActionShortcut = shortcut.modifiers.isEmpty
        guard isModifiedAppShortcut || isUnmodifiedActionShortcut else {
            return nil
        }
        guard let command = ExplorerKeyboardShortcut.command(for: shortcut) else {
            return nil
        }
        let shouldYieldToTextEditing = isToolbarTextInputFocused || isTextEditingResponderFocused
        guard !shouldYieldToTextEditing || command.routesWhileToolbarTextInputFocused else {
            return nil
        }
        guard isCommandEnabled(command) else {
            return nil
        }
        return command
    }
}

extension ExplorerCommand {
    public var routesWhileToolbarTextInputFocused: Bool {
        switch self {
        case .newTab, .closeTab, .nextTab, .previousTab, .focusPath, .focusSearch:
            return true
        case .open, .openInTerminal, .openInVSCode, .chooseOpenWithApplication, .quickLook, .revealInFinder,
             .copyPath, .newFolder, .rename, .duplicate, .extractZip, .compressToZip, .editTags, .undo,
             .selectAll, .addToFavorites, .copy, .cut, .paste,
             .moveToTrash, .calculateFolderSize, .refresh, .clearSearch, .toggleHiddenFiles, .toggleInspector,
             .goBack, .goForward, .goUp:
            return false
        }
    }
}
