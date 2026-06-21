import XCTest
@testable import CaptureStudio

@MainActor
final class EditorViewModelTests: XCTestCase {
    func testAddLayerMarksDocumentDirtyAndSelectsLayer() {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]), isDirty: false)
        let viewModel = EditorViewModel(appState: appState)
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 10, y: 20, width: 80, height: 40),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )

        viewModel.addLayer(layer)

        XCTAssertEqual(appState.currentDocument?.layers, [layer])
        XCTAssertEqual(appState.currentDocument?.selectedLayerID, layer.id)
        XCTAssertTrue(appState.currentDocument?.isDirty ?? false)
    }

    func testUndoRestoresPreviousLayerState() {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        let viewModel = EditorViewModel(appState: appState)
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 10, y: 20, width: 80, height: 40),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )

        viewModel.addLayer(layer)
        viewModel.undo()

        XCTAssertEqual(appState.currentDocument?.layers, [])
        XCTAssertNil(appState.currentDocument?.selectedLayerID)
    }

    func testCreateRectangleLayerFromDrag() throws {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        let viewModel = EditorViewModel(appState: appState)

        viewModel.addLayer(for: .rectangle, from: CGPoint(x: 120, y: 80), to: CGPoint(x: 20, y: 30))

        let layer = try XCTUnwrap(appState.currentDocument?.layers.first)
        XCTAssertEqual(layer.frame, CGRect(x: 20, y: 30, width: 100, height: 50))
        XCTAssertEqual(appState.currentDocument?.selectedLayerID, layer.id)
    }

    func testCreateArrowLayerFromDrag() throws {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        let viewModel = EditorViewModel(appState: appState)

        viewModel.addLayer(for: .arrow, from: CGPoint(x: 10, y: 20), to: CGPoint(x: 90, y: 60))

        let layer = try XCTUnwrap(appState.currentDocument?.layers.first)
        XCTAssertEqual(layer.frame, CGRect(x: 10, y: 20, width: 80, height: 40))
    }

    func testCreateFreehandAndHighlighterLayers() {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        let viewModel = EditorViewModel(appState: appState)
        let points = [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4), CGPoint(x: 8, y: 6)]

        viewModel.addFreehandLayer(for: .pen, points: points)
        viewModel.addFreehandLayer(for: .highlighter, points: points)

        XCTAssertEqual(appState.currentDocument?.layers.count, 2)
        XCTAssertEqual(appState.currentDocument?.layers.first?.frame, CGRect(x: 1, y: 2, width: 7, height: 4))
        XCTAssertEqual(appState.currentDocument?.layers.last?.frame, CGRect(x: 1, y: 2, width: 7, height: 4))
    }

    func testCreateTextLayerAtPoint() throws {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        let viewModel = EditorViewModel(appState: appState)

        viewModel.addTextLayer(at: CGPoint(x: 50, y: 70), text: "Note")

        let layer = try XCTUnwrap(appState.currentDocument?.layers.first)
        XCTAssertEqual(layer.textContent, "Note")
        XCTAssertEqual(layer.frame.origin, CGPoint(x: 50, y: 70))
    }
}
