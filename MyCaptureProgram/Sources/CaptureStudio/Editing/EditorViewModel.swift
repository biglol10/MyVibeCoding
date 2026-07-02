import Foundation
import SwiftUI

@MainActor
public final class EditorViewModel: ObservableObject {
    private let appState: AppState
    private var dragBaseline: EditorSnapshot?

    @Published public var activeTool: EditorTool = .select
    @Published public var style = LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 3)
    @Published public var textSize: CGFloat = 20

    public init(appState: AppState) {
        self.appState = appState
    }

    public var selectedLayer: EditorLayer? {
        guard let document = appState.currentDocument,
              let selectedLayerID = document.selectedLayerID
        else {
            return nil
        }

        return document.layers.first(where: { $0.id == selectedLayerID })
    }

    public var editableText: String {
        selectedLayer?.textContent ?? ""
    }

    public var displayedTextSize: CGFloat {
        selectedLayer?.textFontSize ?? textSize
    }

    public var displayedLineWidth: CGFloat {
        selectedLayer?.lineWidth ?? style.lineWidth
    }

    public func addLayer(_ layer: EditorLayer) {
        mutateDocument { document in
            let snapshot = document.currentSnapshot
            document.undoStack.append(snapshot)
            document.redoStack.removeAll()
            document.layers.append(layer)
            document.selectedLayerID = layer.id
            document.renderedImageData = nil
            document.refreshDirtyState()
        }
    }

    public func addLayer(for tool: EditorTool, from start: CGPoint, to end: CGPoint) {
        let frame = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).standardized
        guard frame.width >= 2, frame.height >= 2 else {
            return
        }

        switch tool {
        case .rectangle:
            addLayer(.rectangle(ShapeLayer(frame: frame, style: style)))
        case .ellipse:
            addLayer(.ellipse(ShapeLayer(frame: frame, style: style)))
        case .redaction:
            addLayer(
                .redaction(
                    RedactionLayer(
                        frame: frame,
                        style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
                    )
                )
            )
        case .arrow:
            addLayer(.arrow(ArrowLayer(start: start, end: end, style: style)))
        case .select, .pen, .highlighter, .text, .ocr:
            return
        }
    }

    public func addFreehandLayer(for tool: EditorTool, points: [CGPoint]) {
        guard points.count > 1 else {
            return
        }

        switch tool {
        case .pen:
            addLayer(.freehand(FreehandLayer(points: points, style: style)))
        case .highlighter:
            addLayer(.highlighter(FreehandLayer(points: points, style: style)))
        case .select, .arrow, .rectangle, .ellipse, .text, .redaction, .ocr:
            return
        }
    }

    public func addTextLayer(at point: CGPoint, text: String = "Text") {
        addLayer(
            .text(
                TextLayer(
                    frame: CGRect(x: point.x, y: point.y, width: 160, height: 48),
                    text: text,
                    fontSize: textSize,
                    style: LayerStyle(strokeColor: .black, fillColor: .yellow, lineWidth: 1)
                )
            )
        )
    }

    public func selectLayer(id: UUID?) {
        mutateDocument { document in
            document.selectedLayerID = id
        }
    }

    public func deleteSelectedLayer() {
        mutateDocument { document in
            guard let selectedLayerID = document.selectedLayerID else {
                return
            }

            let snapshot = document.currentSnapshot
            document.undoStack.append(snapshot)
            document.redoStack.removeAll()
            document.layers.removeAll { $0.id == selectedLayerID }
            document.selectedLayerID = nil
            document.renderedImageData = nil
            document.refreshDirtyState()
        }
    }

    public func undo() {
        mutateDocument { document in
            guard let previous = document.undoStack.popLast() else {
                return
            }

            let current = document.currentSnapshot
            document.redoStack.append(current)
            document.layers = previous.layers
            document.selectedLayerID = previous.selectedLayerID
            document.renderedImageData = nil
            document.refreshDirtyState()
        }
    }

    public func redo() {
        mutateDocument { document in
            guard let next = document.redoStack.popLast() else {
                return
            }

            let current = document.currentSnapshot
            document.undoStack.append(current)
            document.layers = next.layers
            document.selectedLayerID = next.selectedLayerID
            document.renderedImageData = nil
            document.refreshDirtyState()
        }
    }

    public func beginSelectedLayerDrag() {
        guard dragBaseline == nil,
              let document = appState.currentDocument,
              document.selectedLayerID != nil
        else {
            return
        }

        dragBaseline = document.currentSnapshot
    }

    public func updateSelectedLayerDrag(translation: CGSize) {
        guard let baseline = dragBaseline else {
            return
        }

        mutateDocument { document in
            guard let selectedLayerID = baseline.selectedLayerID else {
                return
            }

            var movedLayers = baseline.layers
            guard let index = movedLayers.firstIndex(where: { $0.id == selectedLayerID }) else {
                return
            }

            movedLayers[index].moveBy(dx: translation.width, dy: translation.height)
            document.layers = movedLayers
            document.selectedLayerID = selectedLayerID
            document.renderedImageData = nil
            document.refreshDirtyState()
        }
    }

    public func endSelectedLayerDrag() {
        guard let baseline = dragBaseline else {
            return
        }
        defer { dragBaseline = nil }

        mutateDocument { document in
            guard document.currentSnapshot != baseline else {
                return
            }

            document.undoStack.append(baseline)
            document.redoStack.removeAll()
        }
    }

    public func updateSelectedText(_ text: String) {
        mutateSelectedLayer { layer in
            layer.setTextContent(text)
        }
    }

    public func updateDisplayedTextSize(_ size: CGFloat) {
        textSize = size
        mutateSelectedLayer { layer in
            layer.setTextFontSize(size)
        }
    }

    public func updateDisplayedLineWidth(_ width: CGFloat) {
        style.lineWidth = width
        mutateSelectedLayer { layer in
            layer.setLineWidth(width)
        }
    }

    private func mutateDocument(_ mutate: (inout EditorDocument) -> Void) {
        guard var document = appState.currentDocument, document.kind == .screenshot else {
            return
        }

        mutate(&document)
        appState.currentDocument = document
    }

    private func mutateSelectedLayer(_ mutate: (inout EditorLayer) -> Void) {
        mutateDocument { document in
            guard let selectedLayerID = document.selectedLayerID,
                  let index = document.layers.firstIndex(where: { $0.id == selectedLayerID })
            else {
                return
            }

            var updatedLayer = document.layers[index]
            let originalLayer = updatedLayer
            mutate(&updatedLayer)
            guard updatedLayer != originalLayer else {
                return
            }

            let snapshot = document.currentSnapshot
            document.undoStack.append(snapshot)
            document.redoStack.removeAll()
            document.layers[index] = updatedLayer
            document.renderedImageData = nil
            document.refreshDirtyState()
        }
    }
}
