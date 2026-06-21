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
        XCTAssertEqual(state.activeActionTitle, "Find Large Files")
    }
}
