import XCTest
@testable import MyMacCleanAppSupport

final class SidebarDestinationTests: XCTestCase {
    func testDestinationsExposeDistinctTitlesAndActions() {
        XCTAssertEqual(SidebarDestination.applications.title, "Applications")
        XCTAssertEqual(SidebarDestination.applications.subtitle, "Review installed apps and related files before moving selected items to Trash.")
        XCTAssertFalse(SidebarDestination.applications.subtitle.lowercased().contains("permanent"))
        XCTAssertEqual(SidebarDestination.applications.primaryActionTitle, "Scan Selected")
        XCTAssertEqual(SidebarDestination.orphanFiles.title, "Orphan Files")
        XCTAssertEqual(SidebarDestination.orphanFiles.primaryActionTitle, "Scan Leftovers")
        XCTAssertTrue(SidebarDestination.currentRelease.contains(.orphanFiles))
        XCTAssertEqual(SidebarDestination.deleteHistory.title, "Delete History")
        XCTAssertEqual(SidebarDestination.deleteHistory.primaryActionTitle, "Refresh History")
        XCTAssertEqual(SidebarDestination.startupItems.primaryActionTitle, "Scan Startup Items")
        XCTAssertTrue(SidebarDestination.currentRelease.contains(.startupItems))
        XCTAssertFalse(SidebarDestination.roadmap.contains(.startupItems))
        XCTAssertEqual(SidebarDestination.systemCleanup.primaryActionTitle, "Scan System Junk")
        XCTAssertTrue(SidebarDestination.currentRelease.contains(.largeFiles))
        XCTAssertFalse(SidebarDestination.roadmap.contains(.largeFiles))
        XCTAssertEqual(SidebarDestination.largeFiles.primaryActionTitle, "Scan Large Files")
        XCTAssertEqual(SidebarDestination.maintenance.title, "Developer Cache")
        XCTAssertEqual(SidebarDestination.maintenance.subtitle, "Review build caches that can be regenerated.")
        XCTAssertEqual(SidebarDestination.maintenance.primaryActionTitle, "Scan Developer Caches")
        XCTAssertTrue(SidebarDestination.currentRelease.contains(.maintenance))
        XCTAssertFalse(SidebarDestination.roadmap.contains(.maintenance))
    }
}
