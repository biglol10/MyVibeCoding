import CoreGraphics
import XCTest
@testable import CaptureStudio

final class CaptureSelectionTests: XCTestCase {
    func testSourceRectConvertsPointsToPixelsRelativeToScreen() {
        let selection = CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 100, y: 200, width: 1000, height: 800),
            rect: CGRect(x: 150, y: 260, width: 320, height: 180),
            scale: 2
        )

        XCTAssertEqual(selection.sourceRectInPixels, CGRect(x: 100, y: 1120, width: 640, height: 360))
    }

    func testTinySelectionIsRejected() {
        let selection = CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            rect: CGRect(x: 10, y: 10, width: 4, height: 4),
            scale: 1
        )

        XCTAssertFalse(selection.isUsable)
    }
}
