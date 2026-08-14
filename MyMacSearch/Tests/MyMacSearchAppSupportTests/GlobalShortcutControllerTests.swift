import XCTest
@testable import MyMacSearchAppSupport

final class GlobalShortcutControllerTests: XCTestCase {
    @MainActor
    func testReplacingShortcutUnregistersPreviousHotKey() throws {
        let registrar = HotKeyRegistrarSpy()
        let controller = GlobalShortcutController(registrar: registrar)

        try controller.register(
            GlobalShortcutSetting(keyCode: 49, modifiers: 2_048),
            onPressed: {}
        )
        try controller.register(
            GlobalShortcutSetting(keyCode: 49, modifiers: 2_048 | 256),
            onPressed: {}
        )

        XCTAssertEqual(registrar.unregisteredIDs, [1])
        XCTAssertEqual(registrar.registrations.map(\.id), [1, 2])
    }

    @MainActor
    func testFailedReplacementLeavesNoStaleRegistration() throws {
        let registrar = HotKeyRegistrarSpy()
        let controller = GlobalShortcutController(registrar: registrar)
        try controller.register(GlobalShortcutSetting(), onPressed: {})
        registrar.shouldFail = true

        XCTAssertThrowsError(
            try controller.register(GlobalShortcutSetting(keyCode: 1), onPressed: {})
        )

        XCTAssertEqual(registrar.unregisteredIDs, [1])
        XCTAssertFalse(controller.isRegistered)
    }
}

@MainActor
private final class HotKeyRegistrarSpy: HotKeyRegistering {
    var registrations: [HotKeyRegistration] = []
    var unregisteredIDs: [UInt32] = []
    var shouldFail = false

    func register(
        id: UInt32,
        setting: GlobalShortcutSetting,
        onPressed: @escaping @MainActor () -> Void
    ) throws -> HotKeyRegistration {
        if shouldFail { throw GlobalShortcutError.registrationFailed(-1) }
        let registration = HotKeyRegistration(id: id, opaqueReference: nil)
        registrations.append(registration)
        return registration
    }

    func unregister(_ registration: HotKeyRegistration) {
        unregisteredIDs.append(registration.id)
    }
}
