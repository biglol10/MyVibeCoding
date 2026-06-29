import XCTest
@testable import MyMacFinder

final class InspectorViewWiringTests: XCTestCase {
    @MainActor
    func testInspectorViewAcceptsCommandAndFolderSizeInputs() {
        var receivedCommand: ExplorerCommand?

        let view = InspectorView(
            selection: [],
            calculatedFolderSizes: [:],
            onCommand: { command in
                receivedCommand = command
            }
        )

        XCTAssertNotNil(String(describing: view))
        XCTAssertNil(receivedCommand)
    }
}
