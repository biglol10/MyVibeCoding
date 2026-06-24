import AppKit
@preconcurrency import AVFoundation
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
        let image = try Self.pngImage(from: result.pngData)
        XCTAssertEqual(image.pixelsWide, selection.pixelWidth)
        XCTAssertEqual(image.pixelsHigh, selection.pixelHeight)
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
        try await Self.assertVideo(at: result.fileURL, matches: selection)
    }

    @MainActor
    func testActualThirtySecondRecordingWhenLongQAIsEnabled() async throws {
        try Self.skipUnlessLongQAIsEnabled()
        let selection = try await Self.smallDisplaySelection()
        var settings = AppSettings.defaults
        settings.includeSystemAudio = false
        settings.includeMicrophone = false
        settings.showCursorInRecordings = false
        settings.recordingDurationSeconds = 30
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureStudio-long-recording-\(UUID().uuidString)")
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
        try await Self.assertVideo(at: result.fileURL, matches: selection)

        let asset = AVURLAsset(url: result.fileURL)
        let duration = try await asset.load(.duration).seconds
        XCTAssertGreaterThanOrEqual(duration, 29)
        XCTAssertLessThanOrEqual(duration, 32)
    }

    private static func skipUnlessIntegrationIsEnabled() throws {
        guard ProcessInfo.processInfo.environment["CAPTURE_STUDIO_RUN_INTEGRATION"] == "1" else {
            throw XCTSkip("Set CAPTURE_STUDIO_RUN_INTEGRATION=1 to run ScreenCaptureKit integration tests.")
        }
    }

    private static func skipUnlessLongQAIsEnabled() throws {
        guard ProcessInfo.processInfo.environment["CAPTURE_STUDIO_RUN_LONG_QA"] == "1" else {
            throw XCTSkip("Set CAPTURE_STUDIO_RUN_LONG_QA=1 to run long recording QA tests.")
        }
    }

    private static func smallDisplaySelection() async throws -> CaptureSelection {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = try XCTUnwrap(content.displays.first)
        let screenFrame = CGRect(x: 0, y: 0, width: display.width, height: display.height)
        let scale = NSScreen.screens.first { screen in
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == display.displayID
        }?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        return CaptureSelection(
            displayID: display.displayID,
            screenFrame: screenFrame,
            rect: CGRect(x: 0, y: 0, width: 160, height: 120),
            scale: scale
        )
    }

    private static func pngImage(from data: Data) throws -> NSBitmapImageRep {
        try XCTUnwrap(NSBitmapImageRep(data: data))
    }

    private static func assertVideo(at url: URL, matches selection: CaptureSelection) async throws {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let videoTrack = try XCTUnwrap(tracks.first)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let width = Int(abs(transformedSize.width).rounded())
        let height = Int(abs(transformedSize.height).rounded())

        XCTAssertEqual(width, selection.pixelWidth)
        XCTAssertEqual(height, selection.pixelHeight)
    }
}
