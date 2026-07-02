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
        let basePNG = try TestImageFactory.pngData(width: 80, height: 60, color: .white)
        let layer = EditorLayer.redaction(
            RedactionLayer(
                frame: CGRect(x: 20, y: 20, width: 30, height: 20),
                mode: .blur(radius: 6),
                style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
            )
        )
        let renderer = AppKitImageRenderService()

        let result = try renderer.renderPNG(basePNGData: basePNG, layers: [layer])
        let sampledColor = try TestImageFactory.pixelColor(in: result, x: 30, y: 30)

        XCTAssertGreaterThan(sampledColor.redComponent, 0.7)
        XCTAssertGreaterThan(sampledColor.greenComponent, 0.7)
        XCTAssertGreaterThan(sampledColor.blueComponent, 0.7)
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

    static func pixelColor(in pngData: Data, x: Int, y: Int) throws -> NSColor {
        guard let bitmap = NSBitmapImageRep(data: pngData),
              let color = bitmap.colorAt(x: x, y: y)
        else {
            throw NSError(domain: "TestImageFactory", code: 2)
        }

        return color.usingColorSpace(.deviceRGB) ?? color
    }
}
