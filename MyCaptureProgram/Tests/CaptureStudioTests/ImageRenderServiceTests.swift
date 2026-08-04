import AppKit
import XCTest
@testable import CaptureStudio

final class ImageRenderServiceTests: XCTestCase {
    func testRenderWithoutLayersReturnsValidPNG() throws {
        let basePNG = try TestImageFactory.pngData(width: 80, height: 60, color: .white)
        let renderer = AppKitImageRenderService()

        let result = try renderer.renderPNG(basePNGData: basePNG, layers: [])

        XCTAssertTrue(result.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        XCTAssertGreaterThan(result.count, 0)
    }

    func testVisibleRectangleLayerChangesRenderedPNG() throws {
        let basePNG = try TestImageFactory.pngData(width: 80, height: 60, color: .white)
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 10, y: 10, width: 30, height: 20),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 4)
            )
        )
        let renderer = AppKitImageRenderService()

        let result = try renderer.renderPNG(basePNGData: basePNG, layers: [layer])

        XCTAssertNotEqual(result, basePNG)
        XCTAssertTrue(result.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    func testBlurRedactionDoesNotRenderAsSolidBlackBox() throws {
        let basePNG = try TestImageFactory.checkerboardPNGData(width: 80, height: 60, cellSize: 2)
        let layer = EditorLayer.redaction(
            RedactionLayer(
                frame: CGRect(x: 20, y: 20, width: 30, height: 20),
                mode: .blur(radius: 6),
                style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
            )
        )
        let renderer = AppKitImageRenderService()

        let baseline = try renderer.renderPNG(basePNGData: basePNG, layers: [])
        let result = try renderer.renderPNG(basePNGData: basePNG, layers: [layer])
        let changedPixels = try TestImageFactory.countPixelDifferences(
            baseline,
            result,
            topLeftRegion: CGRect(x: 20, y: 20, width: 30, height: 20)
        )
        let untouchedPixels = try TestImageFactory.countPixelDifferences(
            baseline,
            result,
            topLeftRegion: CGRect(x: 20, y: 45, width: 30, height: 10)
        )
        XCTAssertGreaterThan(changedPixels, 50)
        XCTAssertEqual(untouchedPixels, 0)
    }

    func testSolidRedactionUsesTopLeftEditorCoordinates() throws {
        let basePNG = try TestImageFactory.pngData(width: 20, height: 20, color: .white)
        let layer = EditorLayer.redaction(
            RedactionLayer(
                frame: CGRect(x: 1, y: 1, width: 5, height: 4),
                mode: .solid,
                style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
            )
        )

        let result = try AppKitImageRenderService().renderPNG(basePNGData: basePNG, layers: [layer])
        let topColor = try TestImageFactory.pixelColorFromTopLeft(in: result, x: 3, y: 2)
        let bottomColor = try TestImageFactory.pixelColorFromTopLeft(in: result, x: 3, y: 17)

        XCTAssertLessThan(topColor.redComponent, 0.1)
        XCTAssertGreaterThan(bottomColor.redComponent, 0.9)
    }

    func testArrowRendererIncludesArrowheadAtTopLeftCoordinates() throws {
        let basePNG = try TestImageFactory.pngData(width: 30, height: 24, color: .white)
        let layer = EditorLayer.arrow(
            ArrowLayer(
                start: CGPoint(x: 3, y: 8),
                end: CGPoint(x: 24, y: 8),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )

        let result = try AppKitImageRenderService().renderPNG(basePNGData: basePNG, layers: [layer])
        let redPixelsAwayFromShaft = try TestImageFactory.countPixels(
            in: result,
            topLeftRegion: CGRect(x: 10, y: 1, width: 15, height: 15)
        ) { color, _, y in
            color.redComponent - color.greenComponent > 0.4 && abs(y - 8) > 2
        }

        XCTAssertGreaterThan(redPixelsAwayFromShaft, 3)
    }

    func testFreehandAndHighlighterUseTopLeftEditorCoordinates() throws {
        let basePNG = try TestImageFactory.pngData(width: 40, height: 30, color: .white)
        let layers: [EditorLayer] = [
            .freehand(
                FreehandLayer(
                    points: [CGPoint(x: 3, y: 4), CGPoint(x: 18, y: 4)],
                    style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 3)
                )
            ),
            .highlighter(
                FreehandLayer(
                    points: [CGPoint(x: 22, y: 8), CGPoint(x: 36, y: 8)],
                    style: LayerStyle(strokeColor: .blue, fillColor: .clear, lineWidth: 5)
                )
            )
        ]

        let result = try AppKitImageRenderService().renderPNG(basePNGData: basePNG, layers: layers)
        let topColoredPixels = try TestImageFactory.countPixels(
            in: result,
            topLeftRegion: CGRect(x: 0, y: 0, width: 40, height: 14)
        ) { color, _, _ in
            color.redComponent - color.greenComponent > 0.35
                || color.blueComponent - color.redComponent > 0.2
        }
        let bottomColoredPixels = try TestImageFactory.countPixels(
            in: result,
            topLeftRegion: CGRect(x: 0, y: 18, width: 40, height: 12)
        ) { color, _, _ in
            color.redComponent - color.greenComponent > 0.35
                || color.blueComponent - color.redComponent > 0.2
        }

        XCTAssertGreaterThan(topColoredPixels, 25)
        XCTAssertEqual(bottomColoredPixels, 0)
    }

    func testEllipseAndTextUseTopLeftEditorCoordinates() throws {
        let basePNG = try TestImageFactory.pngData(width: 80, height: 50, color: .white)
        let layers: [EditorLayer] = [
            .ellipse(
                ShapeLayer(
                    frame: CGRect(x: 3, y: 2, width: 24, height: 14),
                    style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 3)
                )
            ),
            .text(
                TextLayer(
                    frame: CGRect(x: 34, y: 2, width: 40, height: 20),
                    text: "Top",
                    fontSize: 14,
                    style: LayerStyle(strokeColor: .black, fillColor: .clear, lineWidth: 1)
                )
            )
        ]

        let result = try AppKitImageRenderService().renderPNG(basePNGData: basePNG, layers: layers)
        let topNonWhitePixels = try TestImageFactory.countPixels(
            in: result,
            topLeftRegion: CGRect(x: 0, y: 0, width: 80, height: 25)
        ) { color, _, _ in
            min(color.redComponent, color.greenComponent, color.blueComponent) < 0.8
        }
        let bottomNonWhitePixels = try TestImageFactory.countPixels(
            in: result,
            topLeftRegion: CGRect(x: 0, y: 30, width: 80, height: 20)
        ) { color, _, _ in
            min(color.redComponent, color.greenComponent, color.blueComponent) < 0.8
        }

        XCTAssertGreaterThan(topNonWhitePixels, 30)
        XCTAssertEqual(bottomNonWhitePixels, 0)
    }
}

private enum TestImageFactory {
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
            throw NSError(domain: "TestImageFactory", code: 1)
        }

        return data
    }

    static func checkerboardPNGData(width: Int, height: Int, cellSize: Int) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "TestImageFactory", code: 5)
        }
        guard let bitmapData = bitmap.bitmapData else {
            throw NSError(domain: "TestImageFactory", code: 6)
        }
        for y in 0..<height {
            for x in 0..<width {
                let isDark = ((x / cellSize) + (y / cellSize)).isMultiple(of: 2)
                let value: UInt8 = isDark ? 0 : 255
                let offset = y * bitmap.bytesPerRow + x * 4
                bitmapData[offset] = value
                bitmapData[offset + 1] = value
                bitmapData[offset + 2] = value
                bitmapData[offset + 3] = 255
            }
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "TestImageFactory", code: 7)
        }
        return data
    }

    static func pixelColor(in pngData: Data, x: Int, y: Int) throws -> NSColor {
        guard let bitmap = NSBitmapImageRep(data: pngData),
              let color = bitmap.colorAt(x: x, y: y)
        else {
            throw NSError(domain: "TestImageFactory", code: 2)
        }

        return color.usingColorSpace(.deviceRGB) ?? color
    }

    static func pixelColorFromTopLeft(in pngData: Data, x: Int, y: Int) throws -> NSColor {
        try pixelColor(in: pngData, x: x, y: y)
    }

    static func countPixels(
        in pngData: Data,
        topLeftRegion: CGRect,
        matching predicate: (NSColor, Int, Int) -> Bool
    ) throws -> Int {
        guard let bitmap = NSBitmapImageRep(data: pngData) else {
            throw NSError(domain: "TestImageFactory", code: 4)
        }

        var count = 0
        for y in Int(topLeftRegion.minY)..<Int(topLeftRegion.maxY) {
            for x in Int(topLeftRegion.minX)..<Int(topLeftRegion.maxX) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if predicate(color, x, y) {
                    count += 1
                }
            }
        }
        return count
    }

    static func countPixelDifferences(
        _ firstPNGData: Data,
        _ secondPNGData: Data,
        topLeftRegion: CGRect
    ) throws -> Int {
        guard let first = NSBitmapImageRep(data: firstPNGData),
              let second = NSBitmapImageRep(data: secondPNGData)
        else {
            throw NSError(domain: "TestImageFactory", code: 8)
        }

        var count = 0
        for y in Int(topLeftRegion.minY)..<Int(topLeftRegion.maxY) {
            for x in Int(topLeftRegion.minX)..<Int(topLeftRegion.maxX) {
                guard let firstColor = first.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let secondColor = second.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else {
                    continue
                }
                let difference = abs(firstColor.redComponent - secondColor.redComponent)
                    + abs(firstColor.greenComponent - secondColor.greenComponent)
                    + abs(firstColor.blueComponent - secondColor.blueComponent)
                if difference > 0.05 {
                    count += 1
                }
            }
        }
        return count
    }
}
