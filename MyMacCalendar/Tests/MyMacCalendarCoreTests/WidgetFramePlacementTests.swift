import Foundation
import XCTest
@testable import MyMacCalendarCore

final class WidgetFramePlacementTests: XCTestCase {
    private let primaryScreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let fallback = CGRect(x: 80, y: 600, width: 260, height: 260)

    func testMostlyOffscreenFrameIsFullyClampedInsideItsDisplay() {
        let stored = CGRect(x: 1910, y: 1070, width: 260, height: 260)

        let result = WidgetFramePlacement.clampedFrame(
            stored,
            visibleFrames: [primaryScreen],
            fallback: fallback
        )

        XCTAssertEqual(result, CGRect(x: 1660, y: 820, width: 260, height: 260))
    }

    func testFrameFromRemovedDisplayReturnsToFallbackDisplay() {
        let stored = CGRect(x: 2500, y: 500, width: 260, height: 260)

        let result = WidgetFramePlacement.clampedFrame(
            stored,
            visibleFrames: [primaryScreen],
            fallback: fallback
        )

        XCTAssertEqual(result, fallback)
    }

    func testNonFiniteStoredOriginUsesSafeFallback() {
        let stored = CGRect(x: CGFloat.nan, y: CGFloat.infinity, width: 260, height: 260)

        let result = WidgetFramePlacement.clampedFrame(
            stored,
            visibleFrames: [primaryScreen],
            fallback: fallback
        )

        XCTAssertEqual(result, fallback)
    }

    func testFrameStaysOnSecondaryDisplayWhenItStillExists() {
        let secondaryScreen = CGRect(x: 1920, y: 0, width: 1440, height: 900)
        let stored = CGRect(x: 3200, y: 820, width: 260, height: 260)

        let result = WidgetFramePlacement.clampedFrame(
            stored,
            visibleFrames: [primaryScreen, secondaryScreen],
            fallback: fallback
        )

        XCTAssertEqual(result, CGRect(x: 3100, y: 640, width: 260, height: 260))
    }
}
