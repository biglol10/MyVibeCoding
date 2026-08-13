import XCTest
@testable import FlowPilotNativeCore

final class CollectionObservationDecisionTests: XCTestCase {
    func testExcludedOrAbsentObservationsResetSessionContinuity() {
        XCTAssertEqual(
            CollectionObservationDecision.decide(
                legacyFlowPilotIsRunning: true,
                snapshotIsAvailable: true
            ),
            .resetAccumulator
        )
        XCTAssertEqual(
            CollectionObservationDecision.decide(
                legacyFlowPilotIsRunning: false,
                snapshotIsAvailable: false
            ),
            .resetAccumulator
        )
    }

    func testAvailableObservationCanBeAccumulated() {
        XCTAssertEqual(
            CollectionObservationDecision.decide(
                legacyFlowPilotIsRunning: false,
                snapshotIsAvailable: true
            ),
            .observe
        )
    }

    func testResetDecisionMakesNextSameIdentitySampleStartFresh() {
        var ids = ["before", "after"]
        let accumulator = ActivitySessionAccumulator(idProvider: { ids.removeFirst() })
        let start = Date(timeIntervalSince1970: 100)
        let first = sample(at: start)
        let next = sample(at: start.addingTimeInterval(5))

        _ = accumulator.observe(first)
        let decision = CollectionObservationDecision.decide(
            legacyFlowPilotIsRunning: false,
            snapshotIsAvailable: false
        )
        if decision == .resetAccumulator {
            accumulator.reset()
        }

        let records = accumulator.observe(next)

        XCTAssertEqual(records.map(\.id), ["after"])
        XCTAssertEqual(records.map(\.durationSeconds), [1])
    }

    private func sample(at date: Date) -> ActivitySample {
        ActivitySample(
            observedAt: date,
            appName: "Codex",
            processName: "Codex",
            windowTitle: "Project",
            domain: nil,
            isIdle: false
        )
    }
}
