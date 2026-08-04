import XCTest
@testable import CaptureStudio

final class RecordingExportServiceTests: XCTestCase {
    func testMissingTrimEndUsesActualAssetDuration() throws {
        let range = try RecordingTrimRangeResolver.resolve(
            startSeconds: 1.25,
            endSeconds: nil,
            assetDurationSeconds: 8.5
        )

        XCTAssertEqual(range, RecordingTrimRange(startSeconds: 1.25, endSeconds: 8.5))
    }

    func testTrimEndBeyondAssetDurationIsClampedToActualEnd() throws {
        let range = try RecordingTrimRangeResolver.resolve(
            startSeconds: 2,
            endSeconds: 30,
            assetDurationSeconds: 6
        )

        XCTAssertEqual(range, RecordingTrimRange(startSeconds: 2, endSeconds: 6))
    }

    func testTrimRangeRejectsNonFiniteOrEmptyRanges() {
        XCTAssertThrowsError(
            try RecordingTrimRangeResolver.resolve(
                startSeconds: .nan,
                endSeconds: nil,
                assetDurationSeconds: 6
            )
        )
        XCTAssertThrowsError(
            try RecordingTrimRangeResolver.resolve(
                startSeconds: 6,
                endSeconds: nil,
                assetDurationSeconds: 6
            )
        )
        XCTAssertThrowsError(
            try RecordingTrimRangeResolver.resolve(
                startSeconds: 1,
                endSeconds: .infinity,
                assetDurationSeconds: 6
            )
        )
    }
}
