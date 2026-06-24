import AppKit
import SwiftUI

struct EditorCanvasView: View {
    let document: EditorDocument
    @ObservedObject var editorViewModel: EditorViewModel
    @State private var draftStart: CGPoint?
    @State private var draftEnd: CGPoint?
    @State private var draftPoints: [CGPoint] = []

    var body: some View {
        GeometryReader { proxy in
            let geometry = canvasGeometry(viewSize: proxy.size)
            ZStack {
                Rectangle()
                    .fill(.quaternary.opacity(0.28))

                if let image = nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()

                    layerOverlay(geometry: geometry)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(false)
                } else {
                    ContentUnavailableView("No Preview", systemImage: "photo")
                }
            }
            .contentShape(Rectangle())
            .gesture(canvasDragGesture(geometry: geometry))
        }
    }

    private var nsImage: NSImage? {
        guard let data = document.currentImageData else {
            return nil
        }

        return NSImage(data: data)
    }

    private func canvasGeometry(viewSize: CGSize) -> EditorCanvasGeometry {
        EditorCanvasGeometry(imageSize: nsImage?.size ?? .zero, viewSize: viewSize)
    }

    private func layerOverlay(geometry: EditorCanvasGeometry) -> some View {
        ZStack {
            ForEach(document.layers) { layer in
                layerView(layer, geometry: geometry)
            }

            if let layer = draftLayer {
                layerView(layer, geometry: geometry)
                    .opacity(0.72)
            }
        }
    }

    @ViewBuilder
    private func layerView(_ layer: EditorLayer, geometry: EditorCanvasGeometry) -> some View {
        let rect = geometry.viewRect(forImageRect: layer.frame)
        switch layer {
        case .rectangle(let shape):
            Rectangle()
                .fill(shape.style.fillColor.color)
                .overlay(Rectangle().stroke(shape.style.strokeColor.color, lineWidth: shape.style.lineWidth))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .overlay(selectionOverlay(rect: rect, layer: layer))
        case .ellipse(let shape):
            Ellipse()
                .fill(shape.style.fillColor.color)
                .overlay(Ellipse().stroke(shape.style.strokeColor.color, lineWidth: shape.style.lineWidth))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .overlay(selectionOverlay(rect: rect, layer: layer))
        case .redaction:
            Rectangle()
                .fill(Color.black)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .overlay(selectionOverlay(rect: rect, layer: layer))
        case .text(let text):
            Text(text.text)
                .font(.system(size: max(10, text.fontSize * rect.height / max(text.frame.height, 1))))
                .foregroundStyle(text.style.strokeColor.color)
                .padding(4)
                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                .background(text.style.fillColor.color)
                .position(x: rect.midX, y: rect.midY)
                .overlay(selectionOverlay(rect: rect, layer: layer))
        case .arrow(let arrow):
            arrowView(arrow, geometry: geometry)
                .overlay(selectionOverlay(rect: rect, layer: layer))
        case .freehand(let freehand):
            polylineView(points: freehand.points, style: freehand.style, geometry: geometry, alpha: 1)
                .overlay(selectionOverlay(rect: rect, layer: layer))
        case .highlighter(let highlighter):
            polylineView(points: highlighter.points, style: highlighter.style, geometry: geometry, alpha: 0.35)
                .overlay(selectionOverlay(rect: rect, layer: layer))
        }
    }

    private func selectionOverlay(rect: CGRect, layer: EditorLayer) -> some View {
        Rectangle()
            .stroke(layer.id == document.selectedLayerID ? Color.accentColor : Color.clear, lineWidth: 1)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func polylineView(points: [CGPoint], style: LayerStyle, geometry: EditorCanvasGeometry, alpha: CGFloat) -> some View {
        Path { path in
            guard let first = points.first else {
                return
            }

            let start = geometry.viewPoint(forImagePoint: first)
            path.move(to: start)
            for point in points.dropFirst() {
                path.addLine(to: geometry.viewPoint(forImagePoint: point))
            }
        }
        .stroke(style.strokeColor.color.opacity(alpha), lineWidth: style.lineWidth)
    }

    private func arrowView(_ arrow: ArrowLayer, geometry: EditorCanvasGeometry) -> some View {
        Path { path in
            let start = geometry.viewPoint(forImagePoint: arrow.start)
            let end = geometry.viewPoint(forImagePoint: arrow.end)
            path.move(to: start)
            path.addLine(to: end)

            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength: CGFloat = 12
            let left = CGPoint(
                x: end.x - headLength * cos(angle - .pi / 6),
                y: end.y - headLength * sin(angle - .pi / 6)
            )
            let right = CGPoint(
                x: end.x - headLength * cos(angle + .pi / 6),
                y: end.y - headLength * sin(angle + .pi / 6)
            )
            path.move(to: end)
            path.addLine(to: left)
            path.move(to: end)
            path.addLine(to: right)
        }
        .stroke(arrow.style.strokeColor.color, lineWidth: arrow.style.lineWidth)
    }

    private var draftLayer: EditorLayer? {
        switch editorViewModel.activeTool {
        case .rectangle, .ellipse, .arrow, .redaction:
            guard let draftStart, let draftEnd else {
                return nil
            }

            return transientDragLayer(from: draftStart, to: draftEnd)
        case .pen:
            guard draftPoints.count > 1 else {
                return nil
            }

            return .freehand(FreehandLayer(points: draftPoints, style: editorViewModel.style))
        case .highlighter:
            guard draftPoints.count > 1 else {
                return nil
            }

            return .highlighter(FreehandLayer(points: draftPoints, style: editorViewModel.style))
        case .select, .text, .ocr:
            return nil
        }
    }

    private func transientDragLayer(from start: CGPoint, to end: CGPoint) -> EditorLayer? {
        let frame = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        switch editorViewModel.activeTool {
        case .rectangle:
            return .rectangle(ShapeLayer(frame: frame, style: editorViewModel.style))
        case .ellipse:
            return .ellipse(ShapeLayer(frame: frame, style: editorViewModel.style))
        case .arrow:
            return .arrow(ArrowLayer(start: start, end: end, style: editorViewModel.style))
        case .redaction:
            return .redaction(
                RedactionLayer(
                    frame: frame,
                    style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
                )
            )
        case .select, .pen, .highlighter, .text, .ocr:
            return nil
        }
    }

    private func canvasDragGesture(geometry: EditorCanvasGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = geometry.imagePoint(forViewPoint: value.location)
                switch editorViewModel.activeTool {
                case .pen, .highlighter:
                    if draftPoints.isEmpty {
                        draftPoints.append(geometry.imagePoint(forViewPoint: value.startLocation))
                    }
                    draftPoints.append(point)
                case .rectangle, .ellipse, .arrow, .redaction:
                    draftStart = geometry.imagePoint(forViewPoint: value.startLocation)
                    draftEnd = point
                case .select, .text, .ocr:
                    break
                }
            }
            .onEnded { value in
                let start = geometry.imagePoint(forViewPoint: value.startLocation)
                let end = geometry.imagePoint(forViewPoint: value.location)
                switch editorViewModel.activeTool {
                case .pen, .highlighter:
                    editorViewModel.addFreehandLayer(for: editorViewModel.activeTool, points: draftPoints)
                case .rectangle, .ellipse, .arrow, .redaction:
                    editorViewModel.addLayer(for: editorViewModel.activeTool, from: start, to: end)
                case .text:
                    editorViewModel.addTextLayer(at: end)
                case .select:
                    selectLayer(at: end)
                case .ocr:
                    break
                }
                clearDraft()
            }
    }

    private func selectLayer(at point: CGPoint) {
        let selected = document.layers.last { layer in
            layer.frame.insetBy(dx: -4, dy: -4).contains(point)
        }
        editorViewModel.selectLayer(id: selected?.id)
    }

    private func clearDraft() {
        draftStart = nil
        draftEnd = nil
        draftPoints = []
    }
}

private extension EditorCanvasGeometry {
    func viewPoint(forImagePoint point: CGPoint) -> CGPoint {
        let rect = imageRectInView
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        return CGPoint(
            x: rect.minX + (point.x / imageSize.width) * rect.width,
            y: rect.minY + (point.y / imageSize.height) * rect.height
        )
    }
}

private extension LayerColor {
    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
