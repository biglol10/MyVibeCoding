import XCTest
@testable import MyMacCleanAppSupport

final class SidebarNavigationStateTests: XCTestCase {
    func testSelectingDestinationUpdatesActivePresentation() {
        var state = SidebarNavigationState()

        XCTAssertEqual(state.selectedDestination, .applications)
        XCTAssertEqual(state.activeTitle, "Applications")
        XCTAssertEqual(state.activeActionTitle, "Scan Selected")

        state.select(.deleteHistory)

        XCTAssertEqual(state.selectedDestination, .deleteHistory)
        XCTAssertEqual(state.activeTitle, "Delete History")
        XCTAssertEqual(state.activeActionTitle, "Refresh History")

        state.select(.largeFiles)

        XCTAssertEqual(state.selectedDestination, .largeFiles)
        XCTAssertEqual(state.activeTitle, "Large Files")
        XCTAssertEqual(state.activeActionTitle, "Scan Large Files")

        state.select(.maintenance)

        XCTAssertEqual(state.selectedDestination, .maintenance)
        XCTAssertEqual(state.activeTitle, "Developer Cache")
        XCTAssertEqual(state.activeActionTitle, "Scan Developer Caches")

        state.select(.startupItems)

        XCTAssertEqual(state.selectedDestination, .startupItems)
        XCTAssertEqual(state.activeTitle, "Startup Items")
        XCTAssertEqual(state.activeActionTitle, "Scan Startup Items")
    }
}
