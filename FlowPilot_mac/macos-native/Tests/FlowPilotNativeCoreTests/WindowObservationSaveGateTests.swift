import XCTest
@testable import FlowPilotNativeCore

final class WindowObservationSaveGateTests: XCTestCase {
    func testAllowsFirstSaveAndThenThrottlesUntilIntervalPasses() {
        var gate = WindowObservationSaveGate(minimumInterval: 60)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertTrue(gate.consumeIfDue(at: start))
        XCTAssertFalse(gate.consumeIfDue(at: start.addingTimeInterval(30)))
        XCTAssertTrue(gate.consumeIfDue(at: start.addingTimeInterval(60)))
    }
}
