import Foundation
import SwiftUI

@MainActor
public final class EditorViewModel: ObservableObject {
    private let appState: AppState

    @Published public var activeTool: EditorTool = .select
    @Published public var style = LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 3)
    @Published public var textSize: CGFloat = 20
    @Published public var blurRadius: CGFloat = 8

    public init(appState: AppState) {
        self.appState = appState
    }

    public func addLayer(_ layer: EditorLayer) {
        mutateDocument { document in
            let snapshot = EditorSnapshot(layers: document.layers, selectedLayerID: document.selectedLayerID)
            document.undoStack.append(snapshot)
            document.redoStack.removeAll()
            document.layers.append(layer)
            document.selectedLayerID = layer.id
            document.renderedImageData = nil
            document.isDirty = true
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

            let snapshot = EditorSnapshot(layers: document.layers, selectedLayerID: document.selectedLayerID)
            document.undoStack.append(snapshot)
            document.redoStack.removeAll()
            document.layers.removeAll { $0.id == selectedLayerID }
            document.selectedLayerID = nil
            document.renderedImageData = nil
            document.isDirty = true
        }
    }

    public func undo() {
        mutateDocument { document in
            guard let previous = document.undoStack.popLast() else {
                return
            }

            let current = EditorSnapshot(layers: document.layers, selectedLayerID: document.selectedLayerID)
            document.redoStack.append(current)
            document.layers = previous.layers
            document.selectedLayerID = previous.selectedLayerID
            document.renderedImageData = nil
            document.isDirty = true
        }
    }

    public func redo() {
        mutateDocument { document in
            guard let next = document.redoStack.popLast() else {
                return
            }

            let current = EditorSnapshot(layers: document.layers, selectedLayerID: document.selectedLayerID)
            document.undoStack.append(current)
            document.layers = next.layers
            document.selectedLayerID = next.selectedLayerID
            document.renderedImageData = nil
            document.isDirty = true
        }
    }

    private func mutateDocument(_ mutate: (inout EditorDocument) -> Void) {
        guard var document = appState.currentDocument, document.kind == .screenshot else {
            return
        }

        mutate(&document)
        appState.currentDocument = document
    }
}
