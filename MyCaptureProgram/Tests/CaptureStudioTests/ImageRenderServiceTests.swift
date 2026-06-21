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
}
