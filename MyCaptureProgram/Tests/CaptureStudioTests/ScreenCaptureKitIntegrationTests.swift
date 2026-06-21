import Foundation
import ScreenCaptureKit
import XCTest
@testable import CaptureStudio

final class ScreenCaptureKitIntegrationTests: XCTestCase {
    @MainActor
    func testActualScreenshotCaptureWhenExplicitlyEnabled() async throws {
        try Self.skipUnlessIntegrationIsEnabled()
        let selection = try await Self.smallDisplaySelection()

        let result = try await ScreenCaptureKitScreenshotService().captureImage(selection: selection)

        XCTAssertGreaterThan(result.pngData.count, 0)
    }

    @MainActor
    func testActualRecordingWhenExplicitlyEnabled() async throws {
        try Self.skipUnlessIntegrationIsEnabled()
        let selection = try await Self.smallDisplaySelection()
        var settings = AppSettings.defaults
        settings.includeSystemAudio = false
        settings.includeMicrophone = false
        settings.showCursorInRecordings = false
        settings.recordingDurationSeconds = 1
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        let result = try await ScreenCaptureKitRecordingService().recordScreen(
            selection: selection,
            to: outputURL,
            settings: settings
        )
        defer { try? FileManager.default.removeItem(at: result.fileURL) }

        let attributes = try FileManager.default.attributesOfItem(atPath: result.fileURL.path)
        let fileSize = try XCTUnwrap(attributes[.size] as? NSNumber)
        XCTAssertGreaterThan(fileSize.intValue, 0)
    }

    private static func skipUnlessIntegrationIsEnabled() throws {
        guard ProcessInfo.processInfo.environment["CAPTURE_STUDIO_RUN_INTEGRATION"] == "1" else {
            throw XCTSkip("Set CAPTURE_STUDIO_RUN_INTEGRATION=1 to run ScreenCaptureKit integration tests.")
        }
    }

    private static func smallDisplaySelection() async throws -> CaptureSelection {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = try XCTUnwrap(content.displays.first)
        let screenFrame = CGRect(x: 0, y: 0, width: display.width, height: display.height)
        return CaptureSelection(
            displayID: display.displayID,
            screenFrame: screenFrame,
            rect: CGRect(x: 0, y: 0, width: 160, height: 120),
            scale: 1
        )
    }
}
