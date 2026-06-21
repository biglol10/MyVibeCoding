import XCTest
@testable import MyMacCleanAppSupport

final class SidebarDestinationTests: XCTestCase {
    func testDestinationsExposeDistinctTitlesAndActions() {
        XCTAssertEqual(SidebarDestination.applications.title, "Applications")
        XCTAssertEqual(SidebarDestination.applications.primaryActionTitle, "Scan Selected")
        XCTAssertEqual(SidebarDestination.orphanFiles.title, "Orphan Files")
        XCTAssertEqual(SidebarDestination.orphanFiles.primaryActionTitle, "Scan Leftovers")
        XCTAssertTrue(SidebarDestination.currentRelease.contains(.orphanFiles))
        XCTAssertEqual(SidebarDestination.deleteHistory.title, "Delete History")
        XCTAssertEqual(SidebarDestination.deleteHistory.primaryActionTitle, "Refresh History")
        XCTAssertEqual(SidebarDestination.startupItems.primaryActionTitle, "Scan Login Items")
        XCTAssertEqual(SidebarDestination.systemCleanup.primaryActionTitle, "Scan System Junk")
        XCTAssertEqual(SidebarDestination.largeFiles.primaryActionTitle, "Find Large Files")
        XCTAssertEqual(SidebarDestination.maintenance.primaryActionTitle, "Run Maintenance Check")
    }
}
