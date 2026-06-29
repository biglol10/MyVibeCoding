import XCTest
@testable import MyMacFinder

final class ExplorerKeyboardShortcutTests: XCTestCase {
    func testCommandShortcutsMapToFileCommands() {
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "c", modifiers: [.command])),
            .copy
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "x", modifiers: [.command])),
            .cut
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "v", modifiers: [.command])),
            .paste
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "d", modifiers: [.command])),
            .duplicate
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "f", modifiers: [.command])),
            .focusSearch
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "l", modifiers: [.command])),
            .focusPath
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "z", modifiers: [.command])),
            .undo
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "a", modifiers: [.command])),
            .selectAll
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "o", modifiers: [.command])),
            .open
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "i", modifiers: [.command])),
            .toggleInspector
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "t", modifiers: [.command])),
            .newTab
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "w", modifiers: [.command])),
            .closeTab
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "up", modifiers: [.command])),
            .goUp
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "down", modifiers: [.command])),
            .open
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "left", modifiers: [.command])),
            .goBack
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "right", modifiers: [.command])),
            .goForward
        )
    }

    func testModifiedShortcutsMapToFileCommands() {
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "n", modifiers: [.command, .shift])),
            .newFolder
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "c", modifiers: [.command, .option])),
            .copyPath
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "r", modifiers: [.command, .option])),
            .revealInFinder
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: ".", modifiers: [.command, .shift])),
            .toggleHiddenFiles
        )
    }

    func testSpecialKeysMapToFileCommands() {
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "return", modifiers: [])),
            .open
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "f2", modifiers: [])),
            .rename
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "delete", modifiers: [.command])),
            .moveToTrash
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "space", modifiers: [])),
            .quickLook
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "escape", modifiers: [])),
            .clearSearch
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "tab", modifiers: [.control])),
            .nextTab
        )
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "tab", modifiers: [.control, .shift])),
            .previousTab
        )
    }

    func testUnknownShortcutReturnsNil() {
        XCTAssertNil(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "p", modifiers: [.command]))
        )
    }
}
