import AppKit
import XCTest
@testable import CaptureStudio

final class FloatingPinServiceTests: XCTestCase {
    @MainActor
    func testClosedPinPanelIsRemovedFromServiceStorage() throws {
        let service = AppKitFloatingPinService()

        try service.pinImage(data: try pngData(), title: "Pinned")
        XCTAssertEqual(service.activePanels.count, 1)

        service.activePanels.first?.close()

        XCTAssertEqual(service.activePanels.count, 0)
    }

    private func pngData() throws -> Data {
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 20, height: 20)).fill()
        image.unlockFocus()

        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }
}
