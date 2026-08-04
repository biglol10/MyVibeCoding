import XCTest
@testable import CaptureStudio

final class ScreenCaptureApplicationMatcherTests: XCTestCase {
    func testMatchesCurrentApplicationByProcessID() {
        XCTAssertTrue(
            ScreenCaptureApplicationMatcher.matches(
                applicationProcessID: 42,
                applicationBundleIdentifier: nil,
                currentProcessID: 42,
                currentBundleIdentifier: "com.capturestudio.mac"
            )
        )
    }

    func testMatchesCurrentApplicationByBundleIdentifierDuringWindowVisibilityRace() {
        XCTAssertTrue(
            ScreenCaptureApplicationMatcher.matches(
                applicationProcessID: 99,
                applicationBundleIdentifier: "com.capturestudio.mac",
                currentProcessID: 42,
                currentBundleIdentifier: "com.capturestudio.mac"
            )
        )
    }

    func testDoesNotMatchAnotherApplication() {
        XCTAssertFalse(
            ScreenCaptureApplicationMatcher.matches(
                applicationProcessID: 99,
                applicationBundleIdentifier: "com.example.other",
                currentProcessID: 42,
                currentBundleIdentifier: "com.capturestudio.mac"
            )
        )
    }
}
