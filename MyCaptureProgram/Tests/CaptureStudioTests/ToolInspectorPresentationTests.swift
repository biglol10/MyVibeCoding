import XCTest
@testable import CaptureStudio

final class ToolInspectorPresentationTests: XCTestCase {
    func testSelectAndOCRHideInspectorControls() {
        XCTAssertFalse(ToolInspectorPresentation.controls(for: .select, selectedLayer: nil).isVisible)
        XCTAssertFalse(ToolInspectorPresentation.controls(for: .ocr, selectedLayer: nil).isVisible)
    }

    func testDrawingToolsShowLineWidthOnly() {
        for tool in [EditorTool.pen, .highlighter, .arrow, .rectangle, .ellipse] {
            let presentation = ToolInspectorPresentation.controls(for: tool, selectedLayer: nil)
            XCTAssertTrue(presentation.showsLineWidth, "\(tool.rawValue)")
            XCTAssertFalse(presentation.showsTextSize, "\(tool.rawValue)")
            XCTAssertFalse(presentation.showsTextContent, "\(tool.rawValue)")
        }
    }

    func testTextToolShowsTextSizeOnly() {
        let presentation = ToolInspectorPresentation.controls(for: .text, selectedLayer: nil)

        XCTAssertFalse(presentation.showsLineWidth)
        XCTAssertTrue(presentation.showsTextSize)
        XCTAssertFalse(presentation.showsTextContent)
        XCTAssertTrue(presentation.isVisible)
    }

    func testRedactionHidesUnusedInspectorControls() {
        let presentation = ToolInspectorPresentation.controls(for: .redaction, selectedLayer: nil)

        XCTAssertFalse(presentation.showsLineWidth)
        XCTAssertFalse(presentation.showsTextSize)
        XCTAssertFalse(presentation.showsTextContent)
        XCTAssertFalse(presentation.isVisible)
    }

    func testSelectToolShowsTextControlsWhenTextLayerIsSelected() {
        let selectedText = EditorLayer.text(
            TextLayer(
                frame: CGRect(x: 10, y: 10, width: 140, height: 40),
                text: "Note",
                fontSize: 18,
                style: LayerStyle(strokeColor: .black, fillColor: .yellow, lineWidth: 1)
            )
        )

        let presentation = ToolInspectorPresentation.controls(for: .select, selectedLayer: selectedText)

        XCTAssertFalse(presentation.showsLineWidth)
        XCTAssertTrue(presentation.showsTextSize)
        XCTAssertTrue(presentation.showsTextContent)
    }

    func testSelectToolShowsLineWidthForSelectedShape() {
        let selectedShape = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 10, y: 10, width: 80, height: 30),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 4)
            )
        )

        let presentation = ToolInspectorPresentation.controls(for: .select, selectedLayer: selectedShape)

        XCTAssertTrue(presentation.showsLineWidth)
        XCTAssertFalse(presentation.showsTextSize)
        XCTAssertFalse(presentation.showsTextContent)
    }
}
