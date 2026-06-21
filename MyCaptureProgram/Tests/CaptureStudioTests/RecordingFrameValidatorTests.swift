import ScreenCaptureKit
import XCTest
@testable import CaptureStudio

final class RecordingFrameValidatorTests: XCTestCase {
    func testOnlyCompleteScreenCaptureFramesAreWritable() {
        XCTAssertTrue(ScreenCaptureFrameValidator.isWritableFrameStatus(SCFrameStatus.complete.rawValue))
        XCTAssertFalse(ScreenCaptureFrameValidator.isWritableFrameStatus(SCFrameStatus.idle.rawValue))
        XCTAssertFalse(ScreenCaptureFrameValidator.isWritableFrameStatus(nil))
    }
}
