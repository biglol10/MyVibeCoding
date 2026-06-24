import CoreGraphics
import XCTest
@testable import CaptureStudio

final class CaptureSelectionTests: XCTestCase {
    func testSourceRectUsesLogicalPointsRelativeToScreen() {
        let selection = CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 100, y: 200, width: 1000, height: 800),
            rect: CGRect(x: 150, y: 260, width: 320, height: 180),
            scale: 2
        )

        XCTAssertEqual(selection.sourceRectInPoints, CGRect(x: 50, y: 560, width: 320, height: 180))
    }

    func testOutputSizeUsesPixels() {
        let selection = CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 100, y: 200, width: 1000, height: 800),
            rect: CGRect(x: 150, y: 260, width: 320, height: 180),
            scale: 2
        )

        XCTAssertEqual(selection.pixelWidth, 640)
        XCTAssertEqual(selection.pixelHeight, 360)
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
