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

        XCTAssertEqual(controller.previewURLs.map(\.path), ["/tmp/new.txt"])
    }

    @MainActor
    func testClearingCurrentGenerationRemovesSelection() {
        let controller = QuickLookPreviewController()
        let generation = controller.updateSelection(URL(fileURLWithPath: "/tmp/current.txt"))

        controller.clearSelection(ifGeneration: generation)

        XCTAssertTrue(controller.previewURLs.isEmpty)
    }

    @MainActor
    func testMultiplePreviewURLsPreserveVisibleOrderAndSelectionIndex() {
        let controller = QuickLookPreviewController()

        controller.updateSelection([
            URL(fileURLWithPath: "/tmp/one.txt"),
            URL(fileURLWithPath: "/tmp/two.txt")
        ], selectedIndex: 1)

        XCTAssertEqual(controller.previewURLs.map(\.path), ["/tmp/one.txt", "/tmp/two.txt"])
        XCTAssertEqual(controller.selectedPreviewIndex, 1)
        XCTAssertEqual(controller.numberOfPreviewItems(in: nil), 2)
    }
}
