import XCTest
@testable import CaptureStudio

final class AppStateTests: XCTestCase {
    @MainActor
    func testDefaultsUseScreenshotRectangleAndNoDocument() {
        let state = AppState()

        XCTAssertEqual(state.captureMode, .screenshot)
        XCTAssertEqual(state.areaType, .rectangle)
        XCTAssertNil(state.currentDocument)
    }

    @MainActor
    func testSelectingRecordKeepsAreaType() {
        let state = AppState()

        state.captureMode = .record

        XCTAssertEqual(state.captureMode, .record)
        XCTAssertEqual(state.areaType, .rectangle)
    }

    func testEditorDocumentDirtyState() {
        let document = EditorDocument(kind: .screenshot, createdAt: Date(timeIntervalSince1970: 10))

        XCTAssertTrue(document.isDirty)
        XCTAssertNil(document.fileURL)
    }

    @MainActor
    func testScreenshotDocumentStoresEditingState() {
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 10, y: 10, width: 100, height: 50),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )

        let document = EditorDocument(
            kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: 10),
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            layers: [layer],
            selectedLayerID: layer.id,
            isDirty: true
        )

        XCTAssertEqual(document.baseImageData, Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(document.layers, [layer])
        XCTAssertEqual(document.selectedLayerID, layer.id)
        XCTAssertTrue(document.hasEdits)
    }
}
