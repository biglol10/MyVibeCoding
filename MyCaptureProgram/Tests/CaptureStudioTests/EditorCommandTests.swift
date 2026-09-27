import AppKit
import XCTest
@testable import CaptureStudio

@MainActor
final class EditorCommandTests: XCTestCase {
    func testResponderActionsDeleteOnlySelectedAnnotationAndSupportUndoRedoCopy() {
        let state = AppState(currentDocument: EditorDocument(kind: .screenshot, data: Data()))
        let model = EditorViewModel(appState: state)
        model.addTextLayer(at: .zero, text: "Keep")
        model.addTextLayer(at: CGPoint(x: 100, y: 100), text: "Delete")
        let target = EditorCommandTarget()
        target.viewModel = model
        var copies = 0
        target.onCopy = { copies += 1 }
        target.delete(nil)
        XCTAssertEqual(state.currentDocument?.layers.map(\.textContent), ["Keep"])
        target.undo(nil)
        XCTAssertEqual(state.currentDocument?.layers.count, 2)
        target.redo(nil)
        XCTAssertEqual(state.currentDocument?.layers.count, 1)
        target.copy(nil)
        XCTAssertEqual(copies, 1)
        state.isFileOperationInProgress = true
        target.undo(nil); target.copy(nil)
        XCTAssertEqual(state.currentDocument?.layers.count, 1)
        XCTAssertEqual(copies, 1)
    }

    func testResizingAndRecoloringPreserveOriginalAndCanBeUndone() {
        let data = Data([1, 2, 3])
        let state = AppState(currentDocument: EditorDocument(kind: .screenshot, data: data))
        let model = EditorViewModel(appState: state)
        model.activeTool = .text
        model.addTextLayer(at: CGPoint(x: 10, y: 20), text: "Note")
        let original = state.currentDocument!.layers[0]
        model.resizeSelectedLayer(width: 300, height: 90)
        model.updateDisplayedStrokeColor(.blue)
        XCTAssertEqual(state.currentDocument?.layers[0].frame.size, CGSize(width: 300, height: 90))
        XCTAssertEqual(state.currentDocument?.layers[0].strokeColor, .blue)
        XCTAssertEqual(state.currentDocument?.baseImageData, data)
        model.undo(); model.undo()
        XCTAssertEqual(state.currentDocument?.layers[0], original)
    }

    func testNewDrawingUsesTheWidthShownForTheSelectedLayer() {
        let state = AppState(currentDocument: EditorDocument(kind: .screenshot, data: Data()))
        let model = EditorViewModel(appState: state)
        model.addLayer(.rectangle(ShapeLayer(frame: CGRect(x: 0, y: 0, width: 50, height: 50),
                                            style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 12))))
        model.style.lineWidth = 3
        model.activeTool = .arrow
        let displayed = model.displayedLineWidth
        model.addLayer(for: .arrow, from: .zero, to: CGPoint(x: 100, y: 100))
        XCTAssertEqual(state.currentDocument?.layers.last?.lineWidth, displayed)
    }
}
