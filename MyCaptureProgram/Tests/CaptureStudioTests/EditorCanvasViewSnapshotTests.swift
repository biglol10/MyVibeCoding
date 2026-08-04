import AppKit
import SwiftUI
import XCTest
@testable import CaptureStudio

@MainActor
final class EditorCanvasViewSnapshotTests: XCTestCase {
    func testFreehandOverlayStaysAlignedWhenPreviewHasHorizontalLetterboxing() throws {
        try assertLayer(
            .freehand(
                FreehandLayer(
                    points: [
                        CGPoint(x: 10, y: 10),
                        CGPoint(x: 50, y: 10)
                    ],
                    style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 6)
                )
            ),
            drawsPixelsMatching: \.isStrongRed,
            near: CGRect(x: 10, y: 10, width: 40, height: 1)
        )
    }

    func testHighlighterOverlayStaysAlignedWhenPreviewHasHorizontalLetterboxing() throws {
        try assertLayer(
            .highlighter(
                FreehandLayer(
                    points: [
                        CGPoint(x: 12, y: 18),
                        CGPoint(x: 70, y: 18)
                    ],
                    style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 8)
                )
            ),
            drawsPixelsMatching: \.isTranslucentRed,
            near: CGRect(x: 12, y: 18, width: 58, height: 1)
        )
    }

    func testShapeOverlaysStayAlignedWhenPreviewHasHorizontalLetterboxing() throws {
        let style = LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 6)

        try assertLayer(
            .rectangle(ShapeLayer(frame: CGRect(x: 16, y: 12, width: 40, height: 28), style: style)),
            drawsPixelsMatching: \.isStrongRed,
            near: CGRect(x: 16, y: 12, width: 40, height: 28)
        )
        try assertLayer(
            .ellipse(ShapeLayer(frame: CGRect(x: 22, y: 20, width: 42, height: 26), style: style)),
            drawsPixelsMatching: \.isStrongRed,
            near: CGRect(x: 22, y: 20, width: 42, height: 26)
        )
    }

    func testArrowOverlayStaysAlignedWhenPreviewHasHorizontalLetterboxing() throws {
        try assertLayer(
            .arrow(
                ArrowLayer(
                    start: CGPoint(x: 20, y: 34),
                    end: CGPoint(x: 78, y: 34),
                    style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 6)
                )
            ),
            drawsPixelsMatching: \.isStrongRed,
            near: CGRect(x: 20, y: 34, width: 58, height: 1)
        )
    }

    func testTextOverlayStaysAlignedWhenPreviewHasHorizontalLetterboxing() throws {
        try assertLayer(
            .text(
                TextLayer(
                    frame: CGRect(x: 30, y: 16, width: 44, height: 24),
                    text: "A",
                    fontSize: 18,
                    style: LayerStyle(strokeColor: .red, fillColor: .yellow, lineWidth: 1)
                )
            ),
            drawsPixelsMatching: \.isYellow,
            near: CGRect(x: 30, y: 16, width: 44, height: 24)
        )
    }

    func testRedactionOverlayStaysAlignedWhenPreviewHasHorizontalLetterboxing() throws {
        try assertLayer(
            .redaction(
                RedactionLayer(
                    frame: CGRect(x: 36, y: 24, width: 38, height: 24),
                    style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
                )
            ),
            drawsPixelsMatching: \.isBlack,
            near: CGRect(x: 36, y: 24, width: 38, height: 24)
        )
    }

    private func assertLayer(
        _ layer: EditorLayer,
        drawsPixelsMatching pixelPredicate: (NSColor) -> Bool,
        near expectedImageRect: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let basePNG = try CanvasSnapshotImageFactory.pngData(width: 160, height: 90, color: .white)
        let document = EditorDocument(kind: .screenshot, data: basePNG, layers: [layer], isDirty: false)
        let appState = AppState()
        appState.currentDocument = document
        let viewModel = EditorViewModel(appState: appState)
        let viewSize = CGSize(width: 1200, height: 500)
        let host = NSHostingView(
            rootView: EditorCanvasView(document: document, editorViewModel: viewModel)
                .frame(width: viewSize.width, height: viewSize.height)
        )
        host.frame = CGRect(origin: .zero, size: viewSize)
        host.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(host.renderedBitmap())
        let pixelBounds = try XCTUnwrap(
            bitmap.boundsOfPixels(matching: pixelPredicate),
            "Expected the layer to render matching pixels.",
            file: file,
            line: line
        )
        let geometry = EditorCanvasGeometry(imageSize: CGSize(width: 160, height: 90), viewSize: viewSize)
        let expectedRenderedRect = renderedBounds(for: layer, fallback: expectedImageRect)
        let expectedRect = geometry.viewRect(forImageRect: expectedRenderedRect)
        let pixelScaleX = CGFloat(bitmap.pixelsWide) / viewSize.width
        let pixelScaleY = CGFloat(bitmap.pixelsHigh) / viewSize.height

        XCTAssertEqual(pixelBounds.minX, expectedRect.minX * pixelScaleX, accuracy: 28, file: file, line: line)
        XCTAssertEqual(pixelBounds.minY, expectedRect.minY * pixelScaleY, accuracy: 28, file: file, line: line)
    }

    private func renderedBounds(for layer: EditorLayer, fallback: CGRect) -> CGRect {
        switch layer {
        case .rectangle(let shape), .ellipse(let shape):
            return shape.frame.insetBy(dx: -shape.style.lineWidth / 2, dy: -shape.style.lineWidth / 2)
        case .freehand(let freehand), .highlighter(let freehand):
            return strokedBounds(
                segments: Array(zip(freehand.points, freehand.points.dropFirst())),
                lineWidth: freehand.style.lineWidth,
                fallback: fallback
            )
        case .arrow(let arrow):
            let angle = atan2(arrow.end.y - arrow.start.y, arrow.end.x - arrow.start.x)
            let headLength: CGFloat = 12
            let left = CGPoint(
                x: arrow.end.x - headLength * cos(angle - .pi / 6),
                y: arrow.end.y - headLength * sin(angle - .pi / 6)
            )
            let right = CGPoint(
                x: arrow.end.x - headLength * cos(angle + .pi / 6),
                y: arrow.end.y - headLength * sin(angle + .pi / 6)
            )
            return strokedBounds(
                segments: [(arrow.start, arrow.end), (arrow.end, left), (arrow.end, right)],
                lineWidth: arrow.style.lineWidth,
                fallback: fallback
            )
        case .redaction, .text:
            return fallback
        }
    }

    private func strokedBounds(
        segments: [(CGPoint, CGPoint)],
        lineWidth: CGFloat,
        fallback: CGRect
    ) -> CGRect {
        guard !segments.isEmpty else {
            return fallback
        }

        let halfWidth = lineWidth / 2
        let segmentBounds = segments.map { start, end -> CGRect in
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length > 0 else {
                return CGRect(x: start.x, y: start.y, width: 0, height: 0)
                    .insetBy(dx: -halfWidth, dy: -halfWidth)
            }

            let extensionX = abs(dy / length) * halfWidth
            let extensionY = abs(dx / length) * halfWidth
            return CGRect(
                x: min(start.x, end.x) - extensionX,
                y: min(start.y, end.y) - extensionY,
                width: abs(dx) + extensionX * 2,
                height: abs(dy) + extensionY * 2
            )
        }
        return segmentBounds.dropFirst().reduce(segmentBounds[0]) { $0.union($1) }
    }
}

private enum CanvasSnapshotImageFactory {
    static func pngData(width: Int, height: Int, color: NSColor) throws -> Data {
        let image = NSImage(size: CGSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "CanvasSnapshotImageFactory", code: 1)
        }

        return data
    }
}

private extension NSView {
    func renderedBitmap() -> NSBitmapImageRep? {
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }

        cacheDisplay(in: bounds, to: bitmap)
        return bitmap
    }
}

private extension NSBitmapImageRep {
    func boundsOfPixels(matching predicate: (NSColor) -> Bool) -> CGRect? {
        var minX = Int.max
        var minY = Int.max
        var maxX = Int.min
        var maxY = Int.min

        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide {
                guard let color = colorAt(x: x, y: y) else {
                    continue
                }

                let calibrated = color.usingColorSpace(.deviceRGB) ?? color
                if predicate(calibrated) {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard minX <= maxX, minY <= maxY else {
            return nil
        }

        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

private extension NSColor {
    var isStrongRed: Bool {
        redComponent > 0.75 && greenComponent < 0.25 && blueComponent < 0.25
    }

    var isTranslucentRed: Bool {
        redComponent > 0.85 && greenComponent > 0.35 && greenComponent < 0.85 && blueComponent > 0.35 && blueComponent < 0.85
    }

    var isYellow: Bool {
        redComponent > 0.75 && greenComponent > 0.65 && blueComponent < 0.25
    }

    var isBlack: Bool {
        redComponent < 0.05 && greenComponent < 0.05 && blueComponent < 0.05
    }
}
