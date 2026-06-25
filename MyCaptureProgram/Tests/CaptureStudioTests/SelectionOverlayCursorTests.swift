import AppKit
import XCTest
@testable import CaptureStudio

final class SelectionOverlayCursorTests: XCTestCase {
    @MainActor
    func testSelectionOverlayUsesCustomPlusCursor() {
        let cursor = SelectionOverlayCursor.cursor

        XCTAssertFalse(cursor === NSCursor.crosshair)
        XCTAssertEqual(cursor.image.size.width, 33, accuracy: 0.1)
        XCTAssertEqual(cursor.image.size.height, 33, accuracy: 0.1)
        XCTAssertEqual(cursor.hotSpot.x, 16, accuracy: 0.1)
        XCTAssertEqual(cursor.hotSpot.y, 16, accuracy: 0.1)
    }

    @MainActor
    func testSelectionOverlayRestoresArrowCursorAfterSelection() {
        XCTAssertTrue(SelectionOverlayCursor.defaultCursor === NSCursor.arrow)
    }

    @MainActor
    func testSelectionCursorCanBeReappliedAfterSystemCursorReset() {
        SelectionOverlayCursor.restoreDefaultCursor()
        XCTAssertFalse(SelectionOverlayCursor.isSelectionCursorActive)

        SelectionOverlayCursor.pushSelectionCursor()
        XCTAssertTrue(SelectionOverlayCursor.isSelectionCursorActive)

        SelectionOverlayCursor.reassertSelectionCursor()
        XCTAssertTrue(SelectionOverlayCursor.isSelectionCursorActive)

        SelectionOverlayCursor.restoreDefaultCursor()
        XCTAssertFalse(SelectionOverlayCursor.isSelectionCursorActive)
    }

    @MainActor
    func testSelectionCursorUsesFrequentReassertionInterval() {
        XCTAssertLessThanOrEqual(SelectionOverlayCursor.reassertionInterval, 0.05)
    }

    @MainActor
    func testSelectionCursorCanHideAndRestoreNativeCursor() {
        SelectionOverlayCursor.restoreDefaultCursor()
        XCTAssertFalse(SelectionOverlayCursor.isNativeCursorHiddenForSelection)

        SelectionOverlayCursor.hideNativeCursorForSelection()
        XCTAssertTrue(SelectionOverlayCursor.isNativeCursorHiddenForSelection)

        SelectionOverlayCursor.restoreDefaultCursor()
        XCTAssertFalse(SelectionOverlayCursor.isNativeCursorHiddenForSelection)
    }

    func testSelectionOverlayReticleDrawsPlusAroundCursorPoint() {
        let center = CGPoint(x: 100, y: 120)
        let segments = SelectionOverlayReticle.lineSegments(centeredAt: center)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].start.x, center.x - 13, accuracy: 0.1)
        XCTAssertEqual(segments[0].start.y, center.y, accuracy: 0.1)
        XCTAssertEqual(segments[0].end.x, center.x + 13, accuracy: 0.1)
        XCTAssertEqual(segments[0].end.y, center.y, accuracy: 0.1)
        XCTAssertEqual(segments[1].start.x, center.x, accuracy: 0.1)
        XCTAssertEqual(segments[1].start.y, center.y - 13, accuracy: 0.1)
        XCTAssertEqual(segments[1].end.x, center.x, accuracy: 0.1)
        XCTAssertEqual(segments[1].end.y, center.y + 13, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(SelectionOverlayReticle.strokeWidth, 2)
    }

    func testEscapeKeyCancelsSelectionOverlay() throws {
        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))

        XCTAssertTrue(SelectionOverlayKeyboardPolicy.isCancelEvent(escape))
    }

    func testSelectionOverlayViewFrameUsesLocalCoordinatesForOffsetScreen() {
        let screenFrame = CGRect(x: -1440, y: 120, width: 1440, height: 900)

        XCTAssertEqual(
            SelectionOverlayGeometry.viewFrame(forScreenFrame: screenFrame),
            CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
    }

    func testSelectionOverlayConvertsLocalSelectionToGlobalScreenCoordinates() {
        let screenFrame = CGRect(x: -1440, y: 120, width: 1440, height: 900)
        let localRect = CGRect(x: 20, y: 30, width: 200, height: 100)

        XCTAssertEqual(
            SelectionOverlayGeometry.globalSelectionRect(localRect: localRect, screenFrame: screenFrame),
            CGRect(x: -1420, y: 150, width: 200, height: 100)
        )
    }

    func testSelectionOverlayCreatesWindowForEveryScreen() {
        let screenFrames = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: -1440, y: 82, width: 1440, height: 900)
        ]

        XCTAssertEqual(
            SelectionOverlayGeometry.overlayWindowFrames(forScreenFrames: screenFrames),
            screenFrames
        )
    }
}
