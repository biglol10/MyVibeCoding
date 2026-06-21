import CoreGraphics
import XCTest
@testable import CaptureStudio

final class EditorCanvasGeometryTests: XCTestCase {
    func testImageRectAspectFitsInsideView() {
        let geometry = EditorCanvasGeometry(
            imageSize: CGSize(width: 1600, height: 900),
            viewSize: CGSize(width: 800, height: 800)
        )

        XCTAssertEqual(geometry.imageRectInView, CGRect(x: 0, y: 175, width: 800, height: 450))
    }

    func testViewPointConvertsToImagePixelPoint() {
        let geometry = EditorCanvasGeometry(
            imageSize: CGSize(width: 1600, height: 900),
            viewSize: CGSize(width: 800, height: 800)
        )

        let point = geometry.imagePoint(forViewPoint: CGPoint(x: 400, y: 400))

        XCTAssertEqual(point.x, 800, accuracy: 0.001)
        XCTAssertEqual(point.y, 450, accuracy: 0.001)
    }

    func testImageRectConvertsToViewRect() {
        let geometry = EditorCanvasGeometry(
            imageSize: CGSize(width: 1600, height: 900),
            viewSize: CGSize(width: 800, height: 800)
        )

        let rect = geometry.viewRect(forImageRect: CGRect(x: 400, y: 225, width: 400, height: 225))

        XCTAssertEqual(rect, CGRect(x: 200, y: 287.5, width: 200, height: 112.5))
    }
}
