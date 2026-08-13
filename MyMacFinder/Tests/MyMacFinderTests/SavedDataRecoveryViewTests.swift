import XCTest
@testable import MyMacFinder

final class SavedDataRecoveryViewTests: XCTestCase {
    func testPresentationHidesRecoveryRowsWithoutErrors() {
        let presentation = SavedDataRecoveryPresentation()

        XCTAssertTrue(presentation.items.isEmpty)
    }

    func testPresentationKeepsEachFailedAreaSeparate() {
        let presentation = SavedDataRecoveryPresentation(
            settingsErrorMessage: "settings failed",
            sidebarErrorMessage: "sidebar failed",
            sessionErrorMessage: "session failed"
        )

        XCTAssertEqual(presentation.items.map(\.area), [.settings, .sidebar, .session])
        XCTAssertEqual(presentation.items.map(\.message), ["settings failed", "sidebar failed", "session failed"])
        XCTAssertEqual(presentation.items.map(\.area.title), ["General Settings", "Sidebar", "Previous Session"])
    }

    func testPresentationOmitsOnlyAreasWithoutErrors() {
        let presentation = SavedDataRecoveryPresentation(
            settingsErrorMessage: nil,
            sidebarErrorMessage: "sidebar failed",
            sessionErrorMessage: nil
        )

        XCTAssertEqual(presentation.items.map(\.area), [.sidebar])
    }
}
