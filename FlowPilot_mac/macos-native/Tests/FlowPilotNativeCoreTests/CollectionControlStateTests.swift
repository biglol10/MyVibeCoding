import XCTest
@testable import FlowPilotNativeCore

final class CollectionControlStateTests: XCTestCase {
    func testPauseAndResumeTransitionsAreIdempotent() {
        var state = CollectionControlState()

        XCTAssertTrue(state.pause())
        XCTAssertTrue(state.isManuallyPaused)
        XCTAssertFalse(state.pause())

        XCTAssertTrue(state.resume())
        XCTAssertFalse(state.isManuallyPaused)
        XCTAssertFalse(state.resume())
    }
}
