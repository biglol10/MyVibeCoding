import Foundation
import XCTest
@testable import MyMacSearchAppSupport

final class QuickLookPreviewControllerTests: XCTestCase {
    @MainActor
    func testStaleClearDoesNotRemoveNewerPreviewSelection() {
        let controller = QuickLookPreviewController()
        let oldGeneration = controller.updateSelection(URL(fileURLWithPath: "/tmp/old.txt"))
        _ = controller.updateSelection(URL(fileURLWithPath: "/tmp/new.txt"))

        controller.clearSelection(ifGeneration: oldGeneration)

        XCTAssertEqual(controller.previewURL?.path, "/tmp/new.txt")
    }

    @MainActor
    func testClearingCurrentGenerationRemovesSelection() {
        let controller = QuickLookPreviewController()
        let generation = controller.updateSelection(URL(fileURLWithPath: "/tmp/current.txt"))

        controller.clearSelection(ifGeneration: generation)

        XCTAssertNil(controller.previewURL)
    }
}
