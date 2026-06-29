import XCTest
@testable import MyMacFinder

final class ExplorerShortcutRoutingTests: XCTestCase {
    func testRoutesEnabledModifiedShortcutsWhenToolbarTextInputIsNotFocused() {
        XCTAssertEqual(
            ExplorerShortcutRouting.command(
                for: ExplorerShortcut(key: "c", modifiers: [.command]),
                isToolbarTextInputFocused: false,
                isCommandEnabled: { $0 == .copy }
            ),
            .copy
        )
        XCTAssertEqual(
            ExplorerShortcutRouting.command(
                for: ExplorerShortcut(key: "tab", modifiers: [.control]),
                isToolbarTextInputFocused: false,
                isCommandEnabled: { $0 == .nextTab }
            ),
            .nextTab
        )
    }

    func testDoesNotRouteDisabledModifiedShortcuts() {
        XCTAssertNil(
            ExplorerShortcutRouting.command(
                for: ExplorerShortcut(key: "c", modifiers: [.command]),
                isToolbarTextInputFocused: false,
                isCommandEnabled: { _ in false }
            )
        )
    }

    func testDoesNotRouteUnmodifiedShortcutsThroughGlobalMonitor() {
        XCTAssertNil(
            ExplorerShortcutRouting.command(
                for: ExplorerShortcut(key: "return", modifiers: []),
                isToolbarTextInputFocused: false,
                isCommandEnabled: { _ in true }
            )
        )
        XCTAssertNil(
            ExplorerShortcutRouting.command(
                for: ExplorerShortcut(key: "space", modifiers: []),
                isToolbarTextInputFocused: false,
                isCommandEnabled: { _ in true }
            )
        )
    }

    func testToolbarTextInputFocusYieldsEditingAndNavigationShortcuts() {
        let shortcuts: [ExplorerShortcut] = [
            ExplorerShortcut(key: "c", modifiers: [.command]),
            ExplorerShortcut(key: "x", modifiers: [.command]),
            ExplorerShortcut(key: "v", modifiers: [.command]),
            ExplorerShortcut(key: "a", modifiers: [.command]),
            ExplorerShortcut(key: "z", modifiers: [.command]),
            ExplorerShortcut(key: "left", modifiers: [.command]),
            ExplorerShortcut(key: "right", modifiers: [.command]),
            ExplorerShortcut(key: "up", modifiers: [.command]),
            ExplorerShortcut(key: "down", modifiers: [.command]),
            ExplorerShortcut(key: "o", modifiers: [.command]),
            ExplorerShortcut(key: "d", modifiers: [.command]),
            ExplorerShortcut(key: "r", modifiers: [.command])
        ]

        for shortcut in shortcuts {
            XCTAssertNil(
                ExplorerShortcutRouting.command(
                    for: shortcut,
                    isToolbarTextInputFocused: true,
                    isCommandEnabled: { _ in true }
                ),
                "\(shortcut) should stay with the focused text input"
            )
        }
    }

    func testToolbarTextInputFocusAllowsAppGlobalShortcuts() {
        let expectations: [(ExplorerShortcut, ExplorerCommand)] = [
            (ExplorerShortcut(key: "t", modifiers: [.command]), .newTab),
            (ExplorerShortcut(key: "w", modifiers: [.command]), .closeTab),
            (ExplorerShortcut(key: "tab", modifiers: [.control]), .nextTab),
            (ExplorerShortcut(key: "tab", modifiers: [.control, .shift]), .previousTab),
            (ExplorerShortcut(key: "l", modifiers: [.command]), .focusPath),
            (ExplorerShortcut(key: "f", modifiers: [.command]), .focusSearch)
        ]

        for (shortcut, command) in expectations {
            XCTAssertEqual(
                ExplorerShortcutRouting.command(
                    for: shortcut,
                    isToolbarTextInputFocused: true,
                    isCommandEnabled: { $0 == command }
                ),
                command
            )
        }
    }
}
