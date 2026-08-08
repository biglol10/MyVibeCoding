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

    func testGIFPlanRejectsNonFiniteOrEmptyAssetDuration() {
        for duration in [Double.nan, .infinity, 0, -1] {
            XCTAssertThrowsError(
                try RecordingGIFPlanResolver.resolve(
                    assetDurationSeconds: duration,
                    maxDurationSeconds: nil
                )
            ) { error in
                XCTAssertEqual(error as? RecordingExportError, .invalidMediaDuration)
            }
        }
    }

    func testGIFPlanRejectsInvalidDurationLimit() {
        for limit in [Double.nan, .infinity, 0, -1] {
            XCTAssertThrowsError(
                try RecordingGIFPlanResolver.resolve(
                    assetDurationSeconds: 10,
                    maxDurationSeconds: limit
                )
            ) { error in
                XCTAssertEqual(error as? RecordingExportError, .invalidGIFDurationLimit)
            }
        }
    }

    func testGIFPlanUsesActualDurationAndIncludesTrailingPartialFrameInterval() throws {
        let plan = try RecordingGIFPlanResolver.resolve(
            assetDurationSeconds: 1.05,
            maxDurationSeconds: 0.5
        )

        XCTAssertEqual(plan.durationSeconds, 0.5)
        XCTAssertEqual(plan.frameIntervalSeconds, 0.2)
        XCTAssertEqual(plan.frameCount, 3)
    }

    func testGIFPlanRejectsUnboundedFrameCounts() {
        XCTAssertThrowsError(
            try RecordingGIFPlanResolver.resolve(
                assetDurationSeconds: 1_000,
                maxDurationSeconds: nil
            )
        ) { error in
            XCTAssertEqual(error as? RecordingExportError, .gifTooLong)
        }
    }
}
