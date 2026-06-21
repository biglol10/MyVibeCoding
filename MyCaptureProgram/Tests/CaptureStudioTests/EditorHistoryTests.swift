import CoreGraphics
import XCTest
@testable import CaptureStudio

final class EditorHistoryTests: XCTestCase {
    func testUndoRestoresPreviousLayerState() {
        let initial = EditorSnapshot(layers: [], selectedLayerID: nil)
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                frame: CGRect(x: 20, y: 20, width: 120, height: 80),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )
        let edited = EditorSnapshot(layers: [layer], selectedLayerID: layer.id)
        var history = EditorHistory(current: edited, undoStack: [initial], redoStack: [])

        history.undo()

        XCTAssertEqual(history.current, initial)
        XCTAssertEqual(history.redoStack, [edited])
    }

    func testRedoRestoresUndoneLayerState() {
        let initial = EditorSnapshot(layers: [], selectedLayerID: nil)
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                frame: CGRect(x: 20, y: 20, width: 120, height: 80),
                style: LayerStyle(strokeColor: .blue, fillColor: .clear, lineWidth: 2)
            )
        )
        let edited = EditorSnapshot(layers: [layer], selectedLayerID: layer.id)
        var history = EditorHistory(current: initial, undoStack: [], redoStack: [edited])

        history.redo()

        XCTAssertEqual(history.current, edited)
        XCTAssertEqual(history.undoStack, [initial])
    }
}
