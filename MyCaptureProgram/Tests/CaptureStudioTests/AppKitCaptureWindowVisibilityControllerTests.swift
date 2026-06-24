import AppKit
import XCTest
@testable import CaptureStudio

final class AppKitCaptureWindowVisibilityControllerTests: XCTestCase {
    @MainActor
    func testSuppressingReappearedMainWindowKeepsOverlayVisibleAndRestoresMainWindow() {
        let mainWindow = TrackingWindow(
            contentRect: NSRect(x: 80, y: 80, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let overlayWindow = TrackingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayWindow.level = .screenSaver
        let controller = AppKitCaptureWindowVisibilityController(windowProvider: { [mainWindow, overlayWindow] })

        controller.hideCaptureWindows()
        XCTAssertEqual(mainWindow.orderOutCallCount, 1)
        XCTAssertFalse(mainWindow.reportedVisible)

        mainWindow.reportedVisible = true
        controller.hideCaptureWindows(excluding: overlayWindow)

        XCTAssertEqual(mainWindow.orderOutCallCount, 2)
        XCTAssertEqual(overlayWindow.orderOutCallCount, 0)
        XCTAssertFalse(mainWindow.reportedVisible)
        XCTAssertTrue(overlayWindow.reportedVisible)

        controller.restoreCaptureWindows()
        XCTAssertEqual(mainWindow.makeKeyAndOrderFrontCallCount, 1)
        XCTAssertTrue(mainWindow.reportedVisible)
    }

    @MainActor
    func testSuppressingWithoutInitialHideLeavesWindowVisible() {
        let mainWindow = TrackingWindow(
            contentRect: NSRect(x: 80, y: 80, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let overlayWindow = TrackingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let controller = AppKitCaptureWindowVisibilityController(windowProvider: { [mainWindow, overlayWindow] })

        controller.hideCaptureWindows(excluding: overlayWindow)

        XCTAssertEqual(mainWindow.orderOutCallCount, 0)
        XCTAssertTrue(mainWindow.reportedVisible)
    }
}

private final class TrackingWindow: NSWindow {
    var reportedVisible = true
    var orderOutCallCount = 0
    var makeKeyAndOrderFrontCallCount = 0

    override var isVisible: Bool {
        reportedVisible
    }

    override func orderOut(_ sender: Any?) {
        orderOutCallCount += 1
        reportedVisible = false
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCallCount += 1
        reportedVisible = true
    }
}
