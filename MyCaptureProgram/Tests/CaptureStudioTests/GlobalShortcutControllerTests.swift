import XCTest
@testable import CaptureStudio

@MainActor
final class GlobalShortcutControllerTests: XCTestCase {
    func testConfigureRegistersCurrentShortcuts() {
        let manager = ShortcutManager(defaults: isolatedDefaults("configure"))
        let registrar = SpyGlobalShortcutRegistrar()
        let controller = GlobalShortcutController(registrar: registrar)

        controller.configure(shortcutManager: manager) { _ in }

        XCTAssertEqual(Set(registrar.bindings.keys), Set(ShortcutDefinition.globalActions))
        XCTAssertFalse(registrar.bindings.keys.contains(.openSettings))
    }

    func testUpdatingBindingReRegistersShortcut() throws {
        let manager = ShortcutManager(defaults: isolatedDefaults("update"))
        let registrar = SpyGlobalShortcutRegistrar()
        let controller = GlobalShortcutController(registrar: registrar)

        controller.configure(shortcutManager: manager) { _ in }
        try manager.setBinding(ShortcutBinding(key: "5", modifiers: [.command]), for: .newScreenshot)

        XCTAssertEqual(registrar.bindings[.newScreenshot], ShortcutBinding(key: "5", modifiers: [.command]))
    }

    func testInvokingRegisteredShortcutCallsActionHandler() {
        let manager = ShortcutManager(defaults: isolatedDefaults("invoke"))
        let registrar = SpyGlobalShortcutRegistrar()
        let controller = GlobalShortcutController(registrar: registrar)
        var invokedActions: [ShortcutAction] = []

        controller.configure(shortcutManager: manager) { action in
            invokedActions.append(action)
        }
        registrar.invoke(.newRecording)

        XCTAssertEqual(invokedActions, [.newRecording])
    }

    func testRegistrationFailureIsPublishedForUnsupportedShortcut() throws {
        let manager = ShortcutManager(defaults: isolatedDefaults("failure"))
        let registrar = SpyGlobalShortcutRegistrar()
        let controller = GlobalShortcutController(registrar: registrar)

        controller.configure(shortcutManager: manager) { _ in }
        try manager.setBinding(ShortcutBinding(key: "가", modifiers: [.command]), for: .newScreenshot)

        XCTAssertEqual(
            manager.registrationFailures[.newScreenshot],
            "The key '가' is not supported for global shortcuts."
        )
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "GlobalShortcutControllerTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class SpyGlobalShortcutRegistrar: GlobalShortcutRegistering {
    var bindings: [ShortcutAction: ShortcutBinding] = [:]
    private var handlers: [ShortcutAction: @MainActor () -> Void] = [:]

    func registerHotKey(
        action: ShortcutAction,
        binding: ShortcutBinding,
        handler: @escaping @MainActor () -> Void
    ) throws {
        if binding.key == "가" {
            throw GlobalShortcutRegistrationError.unsupportedKey(binding.key)
        }

        bindings[action] = binding
        handlers[action] = handler
    }

    func unregisterAll() {
        bindings.removeAll()
        handlers.removeAll()
    }

    @MainActor
    func invoke(_ action: ShortcutAction) {
        handlers[action]?()
    }
}
