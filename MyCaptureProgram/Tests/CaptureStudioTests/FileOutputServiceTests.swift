import XCTest
@testable import CaptureStudio

final class FileOutputServiceTests: XCTestCase {
    func testScreenshotFilenameUsesMacStyleTimestamp() {
        let service = FileOutputService()
        let date = Date(timeIntervalSince1970: 1_782_000_000)

        let filename = service.screenshotFilename(for: date)

        XCTAssertTrue(filename.hasPrefix("Screenshot "))
        XCTAssertTrue(filename.hasSuffix(".png"))
        XCTAssertTrue(filename.contains(" at "))
    }

    func testRecordingFilenameUsesMP4Extension() {
        let service = FileOutputService()
        let date = Date(timeIntervalSince1970: 1_782_000_000)

        let filename = service.recordingFilename(for: date)

        XCTAssertTrue(filename.hasPrefix("Recording "))
        XCTAssertTrue(filename.hasSuffix(".mp4"))
    }

    func testExistingDirectoryIsUsed() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let service = FileOutputService()

        let resolved = service.resolvedOutputDirectory(preferredPath: temporaryDirectory.path)

        XCTAssertEqual(resolved.standardizedFileURL, temporaryDirectory.standardizedFileURL)
    }

    func testMissingDirectoryFallsBackToDesktop() {
        let service = FileOutputService()
        let missingPath = "/path/that/does/not/exist"

        let resolved = service.resolvedOutputDirectory(preferredPath: missingPath)

        XCTAssertTrue(resolved.path.hasSuffix("/Desktop"))
    }

    func testWritesScreenshotPNGDataToConfiguredDirectory() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let service = FileOutputService()
        var settings = AppSettings.defaults
        settings.screenshotFolderPath = temporaryDirectory.path
        let data = Data([0x89, 0x50, 0x4E, 0x47])

        let fileURL = try service.writeScreenshotData(data, settings: settings, date: Date(timeIntervalSince1970: 1_782_000_000))

        XCTAssertEqual(try Data(contentsOf: fileURL), data)
        XCTAssertEqual(fileURL.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
        XCTAssertTrue(fileURL.lastPathComponent.hasSuffix(".png"))
    }

    func testWritesRecordingDataToConfiguredDirectory() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let service = FileOutputService()
        var settings = AppSettings.defaults
        settings.recordingFolderPath = temporaryDirectory.path
        let data = Data([0x00, 0x00, 0x00, 0x18])

        let fileURL = try service.writeRecordingData(data, settings: settings, date: Date(timeIntervalSince1970: 1_782_000_000))

        XCTAssertEqual(try Data(contentsOf: fileURL), data)
        XCTAssertEqual(fileURL.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
        XCTAssertTrue(fileURL.lastPathComponent.hasSuffix(".mp4"))
    }
}
