import XCTest
import SwiftUI
@testable import CaptureStudio

final class ShortcutManagerTests: XCTestCase {
    @MainActor
    func testDefaultBindingsContainAllActions() {
        let manager = ShortcutManager(defaults: isolatedDefaults("defaults"))

        XCTAssertEqual(Set(manager.bindings.keys), Set(ShortcutDefinition.customizableActions))
    }

    @MainActor
    func testCustomBindingPersists() throws {
        let defaults = isolatedDefaults("persist")
        let manager = ShortcutManager(defaults: defaults)
        let binding = ShortcutBinding(key: "5", modifiers: [.command, .shift])

        try manager.setBinding(binding, for: .newScreenshot)

        let reloaded = ShortcutManager(defaults: defaults)
        XCTAssertEqual(reloaded.bindings[.newScreenshot], binding)
    }

    @MainActor
    func testDuplicateBindingThrows() throws {
        let manager = ShortcutManager(defaults: isolatedDefaults("duplicate"))
        let recordingBinding = ShortcutDefinition.defaultBinding(for: .newRecording)

        XCTAssertThrowsError(try manager.setBinding(recordingBinding, for: .newScreenshot)) { error in
            XCTAssertEqual(error as? ShortcutManager.ShortcutError, .duplicateBinding(existingAction: .newRecording))
        }
    }

    @MainActor
    func testResetOneShortcutRestoresDefault() throws {
        let manager = ShortcutManager(defaults: isolatedDefaults("resetOne"))

        try manager.setBinding(ShortcutBinding(key: "5", modifiers: [.command]), for: .newScreenshot)
        manager.resetToDefault(.newScreenshot)

        XCTAssertEqual(manager.bindings[.newScreenshot], ShortcutDefinition.defaultBinding(for: .newScreenshot))
    }

    @MainActor
    func testResetAllShortcutsRestoresDefaults() throws {
        let manager = ShortcutManager(defaults: isolatedDefaults("resetAll"))

        try manager.setBinding(ShortcutBinding(key: "5", modifiers: [.command]), for: .newScreenshot)
        manager.resetAllToDefaults()

        XCTAssertEqual(manager.bindings, ShortcutDefinition.defaultBindings)
    }

    @MainActor
    func testPersistenceEncodingFailureIsExposed() throws {
        let manager = ShortcutManager(defaults: isolatedDefaults("encodingFailure"), encodeBindings: { _ in
            throw ShortcutTestEncodingError.expected
        })

        try manager.setBinding(ShortcutBinding(key: "5", modifiers: [.command]), for: .newScreenshot)

        XCTAssertEqual(manager.persistenceErrorMessage, ShortcutTestEncodingError.expected.localizedDescription)
    }

    func testShortcutBindingMapsToSwiftUIKeyboardShortcutValues() {
        let binding = ShortcutBinding(key: "s", modifiers: [.command, .shift])

        XCTAssertEqual(binding.keyEquivalent, KeyEquivalent("S"))
        XCTAssertEqual(binding.eventModifiers, [.command, .shift])
    }

    func testCustomizableActionsIncludeEveryDefaultShortcut() {
        XCTAssertEqual(ShortcutDefinition.customizableActions, [
            .newScreenshot,
            .newRecording,
            .openSettings
        ])
        XCTAssertEqual(Set(ShortcutDefinition.defaultBindings.keys), Set(ShortcutDefinition.customizableActions))
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "ShortcutManagerTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private enum ShortcutTestEncodingError: LocalizedError {
    case expected

    var errorDescription: String? {
        "expected shortcut encoding failure"
    }
}
