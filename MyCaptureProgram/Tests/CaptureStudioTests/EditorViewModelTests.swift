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

    func testChangingImageLayersClearsOCRThatNoLongerMatchesTheImage() {
        let appState = AppState()
        appState.currentDocument = EditorDocument(
            kind: .screenshot,
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            ocrResult: OCRResult(observations: [
                OCRObservation(
                    text: "old result",
                    confidence: 1,
                    boundingBox: CGRect(x: 1, y: 1, width: 10, height: 4)
                )
            ])
        )
        let viewModel = EditorViewModel(appState: appState)

        viewModel.addLayer(
            .rectangle(
                ShapeLayer(
                    frame: CGRect(x: 10, y: 20, width: 80, height: 40),
                    style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
                )
            )
        )

        XCTAssertNil(appState.currentDocument?.ocrResult)
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

    func testUndoBackToSavedScreenshotClearsDirtyState() {
        let appState = AppState()
        let document = EditorDocument(
            kind: .screenshot,
            fileURL: URL(fileURLWithPath: "/tmp/Screenshot.png"),
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            isDirty: false
        )
        appState.currentDocument = document
        let viewModel = EditorViewModel(appState: appState)
        let layer = EditorLayer.arrow(
            ArrowLayer(
                start: CGPoint(x: 10, y: 10),
                end: CGPoint(x: 60, y: 40),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )

        viewModel.addLayer(layer)
        XCTAssertTrue(appState.currentDocument?.isDirty ?? false)

        viewModel.undo()

        XCTAssertEqual(appState.currentDocument?.layers, [])
        XCTAssertFalse(appState.currentDocument?.isDirty ?? true)
    }

    func testUndoBackToUnsavedCaptureKeepsDirtyState() {
        let appState = AppState()
        appState.currentDocument = EditorDocument(
            kind: .screenshot,
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            isDirty: true
        )
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
        XCTAssertTrue(appState.currentDocument?.isDirty ?? false)
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

    func testCreateHorizontalArrowLayerFromDrag() throws {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        let viewModel = EditorViewModel(appState: appState)

        viewModel.addLayer(for: .arrow, from: CGPoint(x: 10, y: 20), to: CGPoint(x: 90, y: 20))

        let layer = try XCTUnwrap(appState.currentDocument?.layers.first)
        XCTAssertEqual(layer.frame, CGRect(x: 10, y: 20, width: 80, height: 0))
    }

    func testCreateVerticalArrowLayerFromDrag() throws {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        let viewModel = EditorViewModel(appState: appState)

        viewModel.addLayer(for: .arrow, from: CGPoint(x: 40, y: 10), to: CGPoint(x: 40, y: 90))

        let layer = try XCTUnwrap(appState.currentDocument?.layers.first)
        XCTAssertEqual(layer.frame, CGRect(x: 40, y: 10, width: 0, height: 80))
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

    func testUpdateSelectedTextChangesTextLayerAndMarksDirty() throws {
        let appState = AppState()
        let layer = EditorLayer.text(
            TextLayer(
                frame: CGRect(x: 20, y: 20, width: 140, height: 40),
                text: "Text",
                fontSize: 18,
                style: LayerStyle(strokeColor: .black, fillColor: .yellow, lineWidth: 1)
            )
        )
        appState.currentDocument = EditorDocument(
            kind: .screenshot,
            fileURL: URL(fileURLWithPath: "/tmp/Screenshot.png"),
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            layers: [layer],
            selectedLayerID: layer.id,
            isDirty: false
        )
        let viewModel = EditorViewModel(appState: appState)

        viewModel.updateSelectedText("Edited")

        let updatedLayer = try XCTUnwrap(appState.currentDocument?.layers.first)
        XCTAssertEqual(updatedLayer.textContent, "Edited")
        XCTAssertTrue(appState.currentDocument?.isDirty ?? false)
    }

    func testUpdateDisplayedLineWidthUpdatesSelectedShapeLayer() throws {
        let appState = AppState()
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 10, y: 20, width: 80, height: 40),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )
        appState.currentDocument = EditorDocument(
            kind: .screenshot,
            fileURL: URL(fileURLWithPath: "/tmp/Screenshot.png"),
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            layers: [layer],
            selectedLayerID: layer.id,
            isDirty: false
        )
        let viewModel = EditorViewModel(appState: appState)

        viewModel.updateDisplayedLineWidth(9)

        let updatedLayer = try XCTUnwrap(appState.currentDocument?.layers.first)
        XCTAssertEqual(updatedLayer.lineWidth, 9)
        XCTAssertEqual(viewModel.style.lineWidth, 9)
        XCTAssertTrue(appState.currentDocument?.isDirty ?? false)
    }

    func testUpdateDisplayedTextSizeUpdatesSelectedTextLayer() throws {
        let appState = AppState()
        let layer = EditorLayer.text(
            TextLayer(
                frame: CGRect(x: 20, y: 20, width: 140, height: 40),
                text: "Text",
                fontSize: 18,
                style: LayerStyle(strokeColor: .black, fillColor: .yellow, lineWidth: 1)
            )
        )
        appState.currentDocument = EditorDocument(
            kind: .screenshot,
            fileURL: URL(fileURLWithPath: "/tmp/Screenshot.png"),
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            layers: [layer],
            selectedLayerID: layer.id,
            isDirty: false
        )
        let viewModel = EditorViewModel(appState: appState)

        viewModel.updateDisplayedTextSize(26)

        let updatedLayer = try XCTUnwrap(appState.currentDocument?.layers.first)
        XCTAssertEqual(updatedLayer.textFontSize, 26)
        XCTAssertEqual(viewModel.textSize, 26)
        XCTAssertTrue(appState.currentDocument?.isDirty ?? false)
    }

    func testMoveSelectedLayerUpdatesFrameAndUndoRestoresOriginalPosition() throws {
        let appState = AppState()
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 10, y: 20, width: 80, height: 40),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )
        appState.currentDocument = EditorDocument(
            kind: .screenshot,
            fileURL: URL(fileURLWithPath: "/tmp/Screenshot.png"),
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            layers: [layer],
            selectedLayerID: layer.id,
            isDirty: false
        )
        let viewModel = EditorViewModel(appState: appState)

        viewModel.beginSelectedLayerDrag()
        viewModel.updateSelectedLayerDrag(translation: CGSize(width: 15, height: -6))
        let movedLayer = try XCTUnwrap(appState.currentDocument?.layers.first)
        XCTAssertEqual(movedLayer.frame, CGRect(x: 25, y: 14, width: 80, height: 40))
        XCTAssertTrue(appState.currentDocument?.isDirty ?? false)

        viewModel.endSelectedLayerDrag()
        viewModel.undo()

        let restoredLayer = try XCTUnwrap(appState.currentDocument?.layers.first)
        XCTAssertEqual(restoredLayer.frame, CGRect(x: 10, y: 20, width: 80, height: 40))
        XCTAssertFalse(appState.currentDocument?.isDirty ?? true)
    }
}
