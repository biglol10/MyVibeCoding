import XCTest

final class FloatingOnlyModeSourceTests: XCTestCase {
    func testMainWindowCloseButtonHidesWindowForFloatingOnlyMode() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/MainWindowView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("MainWindowCloseAccessor()"))
        XCTAssertTrue(source.contains("MainWindowCloseDelegate: NSObject, NSWindowDelegate"))
        XCTAssertTrue(source.contains("func windowShouldClose(_ sender: NSWindow) -> Bool"))
        XCTAssertTrue(source.contains("sender.orderOut(nil)"))
        XCTAssertTrue(source.contains("return false"))
    }

    func testAppReopenAndMenuBarOpenCalendarBringHiddenMainWindowBack() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/App/AppDelegate.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("func applicationShouldHandleReopen"))
        XCTAssertTrue(source.contains("openMainWindow()"))
        XCTAssertTrue(source.contains("window.title == \"MyMacCalendar\""))
        XCTAssertTrue(source.contains("mainWindow.makeKeyAndOrderFront(nil)"))
    }

    private func sourcePath(_ relativePath: String) -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .path
    }
}
