import XCTest
@testable import FlowPilotNativeCore

final class BrowserBridgeListenerGenerationTests: XCTestCase {
    func testIgnoresStoppedListenerCallbacksAfterReplacementStarts() {
        var generation = BrowserBridgeListenerGeneration()
        let stoppedListener = generation.activate()

        generation.invalidate()
        let replacementListener = generation.activate()

        XCTAssertFalse(generation.isCurrent(stoppedListener))
        XCTAssertTrue(generation.isCurrent(replacementListener))
    }

    func testCancelsAcceptedConnectionTokenAfterListenerRestart() {
        var generation = BrowserBridgeListenerGeneration()
        let acceptedConnectionToken = generation.activate()

        generation.invalidate()
        _ = generation.activate()

        XCTAssertEqual(
            generation.connectionDecision(for: acceptedConnectionToken),
            .cancel
        )
    }

    func testProcessesConnectionTokenOnlyWhileItsListenerIsCurrent() {
        var generation = BrowserBridgeListenerGeneration()
        let acceptedConnectionToken = generation.activate()

        XCTAssertEqual(
            generation.connectionDecision(for: acceptedConnectionToken),
            .process
        )
    }
}
