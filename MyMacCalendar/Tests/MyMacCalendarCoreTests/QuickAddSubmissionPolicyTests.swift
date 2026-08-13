import XCTest
@testable import MyMacCalendarCore

final class QuickAddSubmissionPolicyTests: XCTestCase {
    func testConfirmedDateCanBeSavedImmediately() {
        let result = QuickAddResult(
            title: "병원",
            startDate: Date(timeIntervalSinceReferenceDate: 100),
            endDate: Date(timeIntervalSinceReferenceDate: 100),
            needsConfirmation: false
        )

        XCTAssertEqual(QuickAddSubmissionPolicy().decision(for: result), .save(result))
    }

    func testFallbackDateRequiresExplicitConfirmation() {
        let result = QuickAddResult(
            title: "날짜 없는 일정",
            startDate: Date(timeIntervalSinceReferenceDate: 200),
            endDate: Date(timeIntervalSinceReferenceDate: 200),
            needsConfirmation: true
        )

        XCTAssertEqual(QuickAddSubmissionPolicy().decision(for: result), .confirmFallback(result))
    }

    func testMissingPreviewCannotBeSubmitted() {
        XCTAssertEqual(QuickAddSubmissionPolicy().decision(for: nil), .unavailable)
    }
}
