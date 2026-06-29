import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerCommandTests: XCTestCase {
    func testSelectionCommandsRequireSelection() {
        XCTAssertFalse(ExplorerCommand.rename.isEnabled(selectionCount: 0, canPaste: false))
        XCTAssertTrue(ExplorerCommand.rename.isEnabled(selectionCount: 1, canPaste: false))
        XCTAssertFalse(ExplorerCommand.rename.isEnabled(selectionCount: 2, canPaste: false))

        let selectionRequiredCommands: [ExplorerCommand] = [
            .open,
            .quickLook,
            .revealInFinder,
            .copyPath,
            .duplicate,
            .copy,
            .cut,
            .moveToTrash
        ]

        for command in selectionRequiredCommands {
            XCTAssertFalse(
                command.isEnabled(selectionCount: 0, canPaste: true),
                "\(command) should require at least one selected item"
            )
            XCTAssertTrue(
                command.isEnabled(selectionCount: 2, canPaste: false),
                "\(command) should be enabled when items are selected"
            )
        }
    }

    func testPasteDependsOnClipboardState() {
        XCTAssertFalse(ExplorerCommand.paste.isEnabled(selectionCount: 0, canPaste: false))
        XCTAssertTrue(ExplorerCommand.paste.isEnabled(selectionCount: 0, canPaste: true))
        XCTAssertTrue(ExplorerCommand.paste.isEnabled(selectionCount: 3, canPaste: true))
    }

    func testEmptyAreaCommandsAreAlwaysAvailable() {
        XCTAssertTrue(ExplorerCommand.newFolder.isEnabled(selectionCount: 0, canPaste: false))
        XCTAssertTrue(ExplorerCommand.refresh.isEnabled(selectionCount: 0, canPaste: false))
    }

    func testTabCommandsAreAvailableWithoutSelection() {
        XCTAssertTrue(ExplorerCommand.newTab.isEnabled(selectionCount: 0, canPaste: false))
        XCTAssertTrue(ExplorerCommand.nextTab.isEnabled(selectionCount: 0, canPaste: false))
        XCTAssertTrue(ExplorerCommand.previousTab.isEnabled(selectionCount: 0, canPaste: false))
        XCTAssertFalse(
            ExplorerCommand.closeTab.isEnabled(
                selectionCount: 0,
                canPaste: false,
                canUndo: false,
                canCloseTab: false,
                selectedEntries: [],
                isArchiveLocation: false
            )
        )
        XCTAssertTrue(
            ExplorerCommand.closeTab.isEnabled(
                selectionCount: 0,
                canPaste: false,
                canUndo: false,
                canCloseTab: true,
                selectedEntries: [],
                isArchiveLocation: false
            )
        )
    }

    func testUndoDependsOnUndoState() {
        XCTAssertFalse(
            ExplorerCommand.undo.isEnabled(
                selectionCount: 0,
                canPaste: false,
                canUndo: false,
                selectedEntries: [],
                isArchiveLocation: false
            )
        )
        XCTAssertTrue(
            ExplorerCommand.undo.isEnabled(
                selectionCount: 0,
                canPaste: false,
                canUndo: true,
                selectedEntries: [],
                isArchiveLocation: false
            )
        )
    }

    func testHistoryCommandsDependOnHistoryState() {
        XCTAssertFalse(
            ExplorerCommand.goBack.isEnabled(
                selectionCount: 0,
                canPaste: false,
                canUndo: false,
                canCloseTab: false,
                canGoBack: false,
                canGoForward: true,
                selectedEntries: [],
                isArchiveLocation: false
            )
        )
        XCTAssertTrue(
            ExplorerCommand.goBack.isEnabled(
                selectionCount: 0,
                canPaste: false,
                canUndo: false,
                canCloseTab: false,
                canGoBack: true,
                canGoForward: false,
                selectedEntries: [],
                isArchiveLocation: false
            )
        )
        XCTAssertFalse(
            ExplorerCommand.goForward.isEnabled(
                selectionCount: 0,
                canPaste: false,
                canUndo: false,
                canCloseTab: false,
                canGoBack: true,
                canGoForward: false,
                selectedEntries: [],
                isArchiveLocation: false
            )
        )
        XCTAssertTrue(
            ExplorerCommand.goForward.isEnabled(
                selectionCount: 0,
                canPaste: false,
                canUndo: false,
                canCloseTab: false,
                canGoBack: false,
                canGoForward: true,
                selectedEntries: [],
                isArchiveLocation: false
            )
        )
    }

    func testAddToFavoritesRequiresSingleFilesystemFolder() {
        let folder = FileEntry(
            url: URL(fileURLWithPath: "/tmp/Folder", isDirectory: true),
            name: "Folder",
            kind: .folder,
            typeDescription: "Folder",
            fileExtension: "",
            size: nil,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: true,
            isReadable: true
        )
        let file = FileEntry(
            url: URL(fileURLWithPath: "/tmp/file.txt"),
            name: "file.txt",
            kind: .file,
            typeDescription: "Plain Text Document",
            fileExtension: "txt",
            size: 4,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )

        XCTAssertTrue(
            ExplorerCommand.addToFavorites.isEnabled(
                selectionCount: 1,
                canPaste: false,
                selectedEntries: [folder],
                isArchiveLocation: false
            )
        )
        XCTAssertFalse(
            ExplorerCommand.addToFavorites.isEnabled(
                selectionCount: 1,
                canPaste: false,
                selectedEntries: [file],
                isArchiveLocation: false
            )
        )
        XCTAssertFalse(
            ExplorerCommand.addToFavorites.isEnabled(
                selectionCount: 2,
                canPaste: false,
                selectedEntries: [folder, file],
                isArchiveLocation: false
            )
        )
        XCTAssertFalse(
            ExplorerCommand.addToFavorites.isEnabled(
                selectionCount: 1,
                canPaste: false,
                selectedEntries: [folder],
                isArchiveLocation: true
            )
        )
    }

    func testFolderExternalOpenCommandsRequireSingleFilesystemFolder() {
        let folder = FileEntry(
            url: URL(fileURLWithPath: "/tmp/Folder", isDirectory: true),
            name: "Folder",
            kind: .folder,
            typeDescription: "Folder",
            fileExtension: "",
            size: nil,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: true,
            isReadable: true
        )
        let file = FileEntry(
            url: URL(fileURLWithPath: "/tmp/file.txt"),
            name: "file.txt",
            kind: .file,
            typeDescription: "Plain Text Document",
            fileExtension: "txt",
            size: 4,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )

        for command in [ExplorerCommand.openInTerminal, .openInVSCode] {
            XCTAssertTrue(
                command.isEnabled(
                    selectionCount: 1,
                    canPaste: false,
                    selectedEntries: [folder],
                    isArchiveLocation: false
                )
            )
            XCTAssertFalse(
                command.isEnabled(
                    selectionCount: 1,
                    canPaste: false,
                    selectedEntries: [file],
                    isArchiveLocation: false
                )
            )
            XCTAssertFalse(
                command.isEnabled(
                    selectionCount: 2,
                    canPaste: false,
                    selectedEntries: [folder, folder],
                    isArchiveLocation: false
                )
            )
            XCTAssertFalse(
                command.isEnabled(
                    selectionCount: 1,
                    canPaste: false,
                    selectedEntries: [folder],
                    isArchiveLocation: true
                )
            )
        }
    }

    func testChooseOpenWithApplicationRequiresFilesystemSelection() {
        let file = FileEntry(
            url: URL(fileURLWithPath: "/tmp/file.txt"),
            name: "file.txt",
            kind: .file,
            typeDescription: "Plain Text Document",
            fileExtension: "txt",
            size: 4,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )

        XCTAssertTrue(
            ExplorerCommand.chooseOpenWithApplication.isEnabled(
                selectionCount: 1,
                canPaste: false,
                selectedEntries: [file],
                isArchiveLocation: false
            )
        )
        XCTAssertFalse(
            ExplorerCommand.chooseOpenWithApplication.isEnabled(
                selectionCount: 0,
                canPaste: false,
                selectedEntries: [],
                isArchiveLocation: false
            )
        )
        XCTAssertFalse(
            ExplorerCommand.chooseOpenWithApplication.isEnabled(
                selectionCount: 1,
                canPaste: false,
                selectedEntries: [file],
                isArchiveLocation: true
            )
        )
    }

    func testEditTagsRequiresSingleFilesystemEntry() {
        let file = FileEntry(
            url: URL(fileURLWithPath: "/tmp/file.txt"),
            name: "file.txt",
            kind: .file,
            typeDescription: "Plain Text Document",
            fileExtension: "txt",
            size: 4,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )

        XCTAssertTrue(
            ExplorerCommand.editTags.isEnabled(
                selectionCount: 1,
                canPaste: false,
                selectedEntries: [file],
                isArchiveLocation: false
            )
        )
        XCTAssertFalse(
            ExplorerCommand.editTags.isEnabled(
                selectionCount: 0,
                canPaste: false,
                selectedEntries: [],
                isArchiveLocation: false
            )
        )
        XCTAssertFalse(
            ExplorerCommand.editTags.isEnabled(
                selectionCount: 2,
                canPaste: false,
                selectedEntries: [file, file],
                isArchiveLocation: false
            )
        )
    }
}
