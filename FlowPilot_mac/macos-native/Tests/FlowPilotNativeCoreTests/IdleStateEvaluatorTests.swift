import XCTest
@testable import FlowPilotNativeCore

final class IdleStateEvaluatorTests: XCTestCase {
    func testMarksIdleWhenInputAgeMeetsThreshold() {
        XCTAssertFalse(IdleStateEvaluator.isIdle(secondsSinceLastInput: 299, threshold: 300))
        XCTAssertTrue(IdleStateEvaluator.isIdle(secondsSinceLastInput: 300, threshold: 300))
        XCTAssertTrue(IdleStateEvaluator.isIdle(secondsSinceLastInput: 301, threshold: 300))
    }

    func testRejectsInvalidInputAge() {
        XCTAssertFalse(IdleStateEvaluator.isIdle(secondsSinceLastInput: -.infinity, threshold: 300))
        XCTAssertFalse(IdleStateEvaluator.isIdle(secondsSinceLastInput: .nan, threshold: 300))
    }
}
