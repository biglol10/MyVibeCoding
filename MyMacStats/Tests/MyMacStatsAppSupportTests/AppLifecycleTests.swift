import XCTest

final class AppLifecycleTests: XCTestCase {
    func testMenuBarRefreshIsNotStoppedWhenDashboardWindowDisappears() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appURL = packageRoot.appendingPathComponent("Sources/MyMacStatsApp/MyMacStatsApp.swift")
        let contentViewURL = packageRoot.appendingPathComponent("Sources/MyMacStatsApp/Views/ContentView.swift")
        let popoverURL = packageRoot.appendingPathComponent("Sources/MyMacStatsApp/Views/MenuBarPopoverView.swift")

        let appSource = try String(contentsOf: appURL, encoding: .utf8)
        let contentViewSource = try String(contentsOf: contentViewURL, encoding: .utf8)
        let popoverSource = try String(contentsOf: popoverURL, encoding: .utf8)

        XCTAssertTrue(appSource.contains("MenuBarExtra"))
        XCTAssertTrue(contentViewSource.contains("viewModel.start()"))
        XCTAssertTrue(popoverSource.contains("viewModel.start()"))
        XCTAssertFalse(contentViewSource.contains("viewModel.stop()"))
    }
}
