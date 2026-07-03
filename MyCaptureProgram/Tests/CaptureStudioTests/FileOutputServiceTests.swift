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

    func testSmartScreenshotFilenameUsesAppAndWindowContextWhenEnabled() {
        let service = FileOutputService()
        var settings = AppSettings.defaults
        settings.smartFilenamesEnabled = true
        let context = FileNamingContext(
            applicationName: "Google Chrome",
            windowTitle: "Naver News / Economy: Market <Live>"
        )

        let filename = service.screenshotFilename(
            for: Date(timeIntervalSince1970: 1_782_000_000),
            settings: settings,
            context: context
        )

        XCTAssertTrue(filename.contains("Google Chrome"))
        XCTAssertTrue(filename.contains("Naver News Economy Market Live"))
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains("<"))
        XCTAssertTrue(filename.hasSuffix(".png"))
    }

    func testSmartFilenameSettingCanFallbackToClassicNames() {
        let service = FileOutputService()
        var settings = AppSettings.defaults
        settings.smartFilenamesEnabled = false
        let context = FileNamingContext(applicationName: "Chrome", windowTitle: "Ignored")

        let filename = service.screenshotFilename(
            for: Date(timeIntervalSince1970: 1_782_000_000),
            settings: settings,
            context: context
        )

        XCTAssertTrue(filename.hasPrefix("Screenshot "))
        XCTAssertFalse(filename.contains("Chrome"))
    }

    func testTrimmedRecordingAndGIFURLsUseExpectedExtensions() {
        let service = FileOutputService()
        var settings = AppSettings.defaults
        settings.smartFilenamesEnabled = true
        let context = FileNamingContext(applicationName: "Codex", windowTitle: "Bug Report")

        let trimmed = service.trimmedRecordingURL(
            settings: settings,
            date: Date(timeIntervalSince1970: 1_782_000_000),
            context: context
        )
        let gif = service.gifRecordingURL(
            settings: settings,
            date: Date(timeIntervalSince1970: 1_782_000_000),
            context: context
        )

        XCTAssertEqual(trimmed.pathExtension, "mp4")
        XCTAssertEqual(gif.pathExtension, "gif")
        XCTAssertTrue(trimmed.lastPathComponent.contains("Trimmed"))
        XCTAssertTrue(gif.lastPathComponent.contains("GIF"))
    }

    func testExistingDirectoryIsUsed() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let service = FileOutputService()

        let resolved = service.resolvedOutputDirectory(preferredPath: temporaryDirectory.path)

        XCTAssertEqual(resolved.standardizedFileURL, temporaryDirectory.standardizedFileURL)
    }

    func testDirectoryWithSpacesAndKoreanCharactersIsUsed() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Capture QA \(UUID().uuidString) 한글 폴더", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let service = FileOutputService()
        var settings = AppSettings.defaults
        settings.screenshotFolderPath = temporaryDirectory.path
        let data = Data([0x89, 0x50, 0x4E, 0x47])

        let fileURL = try service.writeScreenshotData(data, settings: settings, date: Date(timeIntervalSince1970: 1_782_000_000))

        XCTAssertEqual(try Data(contentsOf: fileURL), data)
        XCTAssertEqual(fileURL.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
    }

    func testMissingDirectoryFallsBackToDesktop() {
        let service = FileOutputService()
        let missingPath = "/path/that/does/not/exist"

        let resolved = service.resolvedOutputDirectory(preferredPath: missingPath)

        XCTAssertTrue(resolved.path.hasSuffix("/Desktop"))
    }

    func testFilePathFallsBackToDesktopInsteadOfBeingTreatedAsDirectory() throws {
        let temporaryFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureStudio-output-\(UUID().uuidString).txt")
        try Data("not a directory".utf8).write(to: temporaryFile)
        let service = FileOutputService()

        let resolved = service.resolvedOutputDirectory(preferredPath: temporaryFile.path)

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

    func testWritingTwoScreenshotsInSameSecondDoesNotOverwriteFirstFile() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let service = FileOutputService()
        var settings = AppSettings.defaults
        settings.screenshotFolderPath = temporaryDirectory.path
        let date = Date(timeIntervalSince1970: 1_782_000_000)
        let firstData = Data([0x89, 0x50, 0x4E, 0x47, 0x01])
        let secondData = Data([0x89, 0x50, 0x4E, 0x47, 0x02])

        let firstURL = try service.writeScreenshotData(firstData, settings: settings, date: date)
        let secondURL = try service.writeScreenshotData(secondData, settings: settings, date: date)

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(try Data(contentsOf: firstURL), firstData)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondData)
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

    func testMovingTwoRecordingsInSameSecondDoesNotOverwriteFirstFile() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let service = FileOutputService()
        var settings = AppSettings.defaults
        settings.recordingFolderPath = temporaryDirectory.path
        let date = Date(timeIntervalSince1970: 1_782_000_000)
        let firstSourceURL = temporaryDirectory.appendingPathComponent("first-source.mp4")
        let secondSourceURL = temporaryDirectory.appendingPathComponent("second-source.mp4")
        let firstData = Data([0x00, 0x00, 0x00, 0x18, 0x01])
        let secondData = Data([0x00, 0x00, 0x00, 0x18, 0x02])
        try firstData.write(to: firstSourceURL)
        try secondData.write(to: secondSourceURL)

        let firstURL = try service.moveRecordingFile(from: firstSourceURL, settings: settings, date: date)
        let secondURL = try service.moveRecordingFile(from: secondSourceURL, settings: settings, date: date)

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(try Data(contentsOf: firstURL), firstData)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondData)
    }
}
