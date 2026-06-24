import AppKit
import XCTest
@testable import CaptureStudio

final class ScreenshotImageCropperTests: XCTestCase {
    func testCropsLargeScreenCaptureCanvasToSelectionSize() throws {
        let selection = CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 300, height: 200),
            rect: CGRect(x: 0, y: 0, width: 120, height: 80),
            scale: 1
        )
        let sourceImage = try makeImage(width: 300, height: 200) { context in
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            context.setFillColor(NSColor.systemRed.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }

        let cropped = try XCTUnwrap(ScreenshotImageCropper.crop(sourceImage, to: selection))

        XCTAssertEqual(cropped.width, 120)
        XCTAssertEqual(cropped.height, 80)
    }

    func testLeavesAlreadyCroppedCaptureUnchanged() throws {
        let selection = CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 300, height: 200),
            rect: CGRect(x: 0, y: 0, width: 120, height: 80),
            scale: 1
        )
        let sourceImage = try makeImage(width: 120, height: 80) { context in
            context.setFillColor(NSColor.systemBlue.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }

        let cropped = try XCTUnwrap(ScreenshotImageCropper.crop(sourceImage, to: selection))

        XCTAssertEqual(cropped.width, 120)
        XCTAssertEqual(cropped.height, 80)
    }

    private func makeImage(
        width: Int,
        height: Int,
        draw: (CGContext) -> Void
    ) throws -> CGImage {
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
            throw XCTSkip("Could not create bitmap")
        }

        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext)
        draw(context)

        return try XCTUnwrap(bitmap.cgImage)
    }
}
