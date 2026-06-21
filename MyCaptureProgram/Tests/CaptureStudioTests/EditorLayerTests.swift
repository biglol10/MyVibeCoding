import CoreGraphics
import XCTest
@testable import CaptureStudio

final class EditorLayerTests: XCTestCase {
    func testShapeLayerMovesByDelta() {
        var layer = EditorLayer.rectangle(
            ShapeLayer(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                frame: CGRect(x: 10, y: 20, width: 100, height: 80),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 4)
            )
        )

        layer.moveBy(dx: 5, dy: -8)

        XCTAssertEqual(layer.frame, CGRect(x: 15, y: 12, width: 100, height: 80))
    }

    func testFreehandLayerFrameBoundsAllPoints() {
        let layer = EditorLayer.freehand(
            FreehandLayer(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                points: [
                    CGPoint(x: 20, y: 40),
                    CGPoint(x: 60, y: 10),
                    CGPoint(x: 90, y: 70)
                ],
                style: LayerStyle(strokeColor: .blue, fillColor: .clear, lineWidth: 3)
            )
        )

        XCTAssertEqual(layer.frame, CGRect(x: 20, y: 10, width: 70, height: 60))
    }

    func testTextLayerStoresContentAndStyle() {
        let layer = EditorLayer.text(
            TextLayer(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                frame: CGRect(x: 30, y: 40, width: 220, height: 64),
                text: "Release blocker",
                fontSize: 24,
                style: LayerStyle(strokeColor: .clear, fillColor: .yellow, lineWidth: 1)
            )
        )

        XCTAssertEqual(layer.id, UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
        XCTAssertEqual(layer.frame, CGRect(x: 30, y: 40, width: 220, height: 64))
        XCTAssertEqual(layer.textContent, "Release blocker")
    }
}
