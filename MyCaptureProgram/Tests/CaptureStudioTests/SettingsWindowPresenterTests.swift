import AppKit
import XCTest
@testable import CaptureStudio

@MainActor
final class SettingsWindowPresenterTests: XCTestCase {
    func testPresentRaisesExistingSettingsWindowAfterOpeningIt() {
        let settingsWindow = SettingsWindowSpy()
        settingsWindow.identifier = NSUserInterfaceItemIdentifier("com_apple_SwiftUI_Settings_window")
        let mainWindow = SettingsWindowSpy()
        var events: [String] = []
        let presenter = AppKitSettingsWindowPresenter(
            windowProvider: { [mainWindow, settingsWindow] },
            activateApplication: { events.append("activate") },
            showSettingsFallback: { events.append("fallback") },
            schedule: { action in
                events.append("schedule")
                action()
            }
        )

        presenter.present {
            events.append("open")
        }

        XCTAssertEqual(events, ["open", "activate", "schedule", "activate"])
        XCTAssertEqual(settingsWindow.makeKeyAndOrderFrontCallCount, 1)
        XCTAssertEqual(mainWindow.makeKeyAndOrderFrontCallCount, 0)
    }

    func testPresentFallsBackToApplicationSettingsActionWhenWindowIsNotDiscoverable() {
        var fallbackCallCount = 0
        let presenter = AppKitSettingsWindowPresenter(
            windowProvider: { [] },
            activateApplication: {},
            showSettingsFallback: { fallbackCallCount += 1 },
            schedule: { $0() }
        )

        presenter.present(openSettings: {})

        XCTAssertEqual(fallbackCallCount, 1)
    }
}

@MainActor
private final class SettingsWindowSpy: NSWindow {
    private(set) var makeKeyAndOrderFrontCallCount = 0

    override func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCallCount += 1
    }
}
