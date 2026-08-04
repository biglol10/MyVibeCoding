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

    func testTrimmedRecordingAndGIFURLsUseExpectedExtensions() throws {
        let service = FileOutputService()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        var settings = AppSettings.defaults
        settings.smartFilenamesEnabled = true
        settings.recordingFolderPath = temporaryDirectory.path
        let context = FileNamingContext(applicationName: "Codex", windowTitle: "Bug Report")

        let trimmed = try service.trimmedRecordingURL(
            settings: settings,
            date: Date(timeIntervalSince1970: 1_782_000_000),
            context: context
        )
        let gif = try service.gifRecordingURL(
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

        let resolved = try service.resolvedOutputDirectory(preferredPath: temporaryDirectory.path)

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

    func testMissingDirectoryFailsInsteadOfSavingToDesktop() {
        let service = FileOutputService()
        let missingPath = "/path/that/does/not/exist"

        XCTAssertThrowsError(try service.resolvedOutputDirectory(preferredPath: missingPath)) { error in
            XCTAssertEqual(error as? FileOutputError, .outputDirectoryUnavailable(missingPath))
        }
    }

    func testFilePathFailsInsteadOfBeingTreatedAsDirectory() throws {
        let temporaryFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureStudio-output-\(UUID().uuidString).txt")
        try Data("not a directory".utf8).write(to: temporaryFile)
        let service = FileOutputService()

        XCTAssertThrowsError(try service.resolvedOutputDirectory(preferredPath: temporaryFile.path)) { error in
            XCTAssertEqual(error as? FileOutputError, .outputDirectoryUnavailable(temporaryFile.path))
        }
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

    func testMovingRecordingRejectsSourceThatNoLongerMatchesExpectedIdentity() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = rootDirectory.appendingPathComponent("source", isDirectory: true)
        let outputDirectory = rootDirectory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let sourceURL = sourceDirectory.appendingPathComponent("recording.mp4")
        let movedOriginalURL = sourceDirectory.appendingPathComponent("original.mp4")
        let replacementData = Data("replacement".utf8)
        try Data("original".utf8).write(to: sourceURL)
        let originalIdentity = try CaptureFileIdentity.existingFile(at: sourceURL)
        try FileManager.default.moveItem(at: sourceURL, to: movedOriginalURL)
        try replacementData.write(to: sourceURL)
        var settings = AppSettings.defaults
        settings.recordingFolderPath = outputDirectory.path

        XCTAssertThrowsError(
            try FileOutputService().moveRecordingFile(
                from: sourceURL,
                expectedSourceIdentity: originalIdentity,
                settings: settings
            )
        ) { error in
            XCTAssertEqual(error as? FileOutputError, .sourceFileChanged)
        }

        XCTAssertEqual(try Data(contentsOf: sourceURL), replacementData)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).isEmpty)
    }

    @MainActor
    func testAsyncRecordingMoveExecutesFileIOOffMainThread() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = rootDirectory.appendingPathComponent("source", isDirectory: true)
        let outputDirectory = rootDirectory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let sourceURL = sourceDirectory.appendingPathComponent("recording.mp4")
        try Data(repeating: 0x5A, count: 128 * 1_024).write(to: sourceURL)
        let sourceIdentity = try CaptureFileIdentity.existingFile(at: sourceURL)
        let observation = ThreadObservation()
        let service = FileOutputService(
            fileManager: .default,
            operationObserver: { observation.recordCurrentThread() }
        )
        var settings = AppSettings.defaults
        settings.recordingFolderPath = outputDirectory.path

        let resultURL = try await service.moveRecordingFileAsync(
            from: sourceURL,
            expectedSourceIdentity: sourceIdentity,
            settings: settings
        )

        XCTAssertEqual(observation.mainThreadValues, [false])
        XCTAssertTrue(FileManager.default.fileExists(atPath: resultURL.path))
    }

    func testAvailableRecordingURLsDoNotCollideBeforeEitherFileExists() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        var settings = AppSettings.defaults
        settings.recordingFolderPath = temporaryDirectory.path
        let service = FileOutputService()
        let date = Date(timeIntervalSince1970: 1_782_000_000)

        let firstURL = try service.availableRecordingURL(settings: settings, date: date)
        let secondURL = try service.availableRecordingURL(settings: settings, date: date)

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testSmartFilenameWithLongEmojiTitleFitsFileSystemComponentLimit() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        var settings = AppSettings.defaults
        settings.screenshotFolderPath = temporaryDirectory.path
        settings.smartFilenamesEnabled = true
        let context = FileNamingContext(
            applicationName: "CaptureStudio",
            windowTitle: String(repeating: "😀", count: 300)
        )

        let outputURL = try FileOutputService().writeScreenshotData(
            Data([0x89, 0x50, 0x4E, 0x47]),
            settings: settings,
            date: Date(timeIntervalSince1970: 1_782_000_000),
            context: context
        )

        XCTAssertLessThanOrEqual(outputURL.lastPathComponent.utf8.count, 255)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testConcurrentScreenshotWritesAllocateDistinctFilesWithoutOverwriting() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let results = ConcurrentWriteResults()
        let directoryPath = temporaryDirectory.path
        let date = Date(timeIntervalSince1970: 1_782_000_000)

        DispatchQueue.concurrentPerform(iterations: 12) { index in
            var settings = AppSettings.defaults
            settings.screenshotFolderPath = directoryPath
            do {
                let url = try FileOutputService().writeScreenshotData(
                    Data([UInt8(index)]),
                    settings: settings,
                    date: date
                )
                results.append(url: url)
            } catch {
                results.append(error: error)
            }
        }

        XCTAssertTrue(results.errors.isEmpty)
        XCTAssertEqual(results.urls.count, 12)
        XCTAssertEqual(Set(results.urls).count, 12)
        XCTAssertEqual(
            Set(try results.urls.compactMap { try Data(contentsOf: $0).first }),
            Set((0..<12).map(UInt8.init))
        )
    }

    func testConcurrentRecordingMovesAllocateDistinctFilesWithoutOverwriting() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let results = ConcurrentWriteResults()
        let directoryPath = temporaryDirectory.path
        let date = Date(timeIntervalSince1970: 1_782_000_000)
        let iterationCount = 40

        DispatchQueue.concurrentPerform(iterations: iterationCount) { index in
            var settings = AppSettings.defaults
            settings.recordingFolderPath = directoryPath
            let sourceURL = temporaryDirectory.appendingPathComponent("source-\(index).mp4")
            do {
                try Data([UInt8(index)]).write(to: sourceURL)
                let url = try FileOutputService().moveRecordingFile(
                    from: sourceURL,
                    settings: settings,
                    date: date
                )
                results.append(url: url)
            } catch {
                results.append(error: error)
            }
        }

        XCTAssertTrue(results.errors.isEmpty, "Unexpected move errors: \(results.errors)")
        XCTAssertEqual(results.urls.count, iterationCount)
        XCTAssertEqual(Set(results.urls).count, iterationCount)
        XCTAssertEqual(
            Set(try results.urls.compactMap { try Data(contentsOf: $0).first }),
            Set((0..<iterationCount).map(UInt8.init))
        )
        for index in 0..<iterationCount {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: temporaryDirectory.appendingPathComponent("source-\(index).mp4").path
                )
            )
        }
    }

    func testExclusiveCopyFallbackCopiesDataWithoutOverwriting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("source.bin")
        let destinationURL = directory.appendingPathComponent("destination.bin")
        let sourceData = Data(repeating: 0x5A, count: 128 * 1_024)
        try sourceData.write(to: sourceURL)

        try ExclusiveFilePublisher.copyExclusively(from: sourceURL, to: destinationURL)

        XCTAssertEqual(try Data(contentsOf: destinationURL), sourceData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testExclusiveCopyFallbackPreservesExistingDestination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("source.bin")
        let destinationURL = directory.appendingPathComponent("destination.bin")
        try Data("source".utf8).write(to: sourceURL)
        try Data("existing".utf8).write(to: destinationURL)

        XCTAssertThrowsError(
            try ExclusiveFilePublisher.copyExclusively(from: sourceURL, to: destinationURL)
        ) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .EEXIST)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("existing".utf8))
        XCTAssertEqual(try Data(contentsOf: sourceURL), Data("source".utf8))
    }

    func testExclusiveCopyRejectsSourceThatNoLongerMatchesExpectedIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("source.bin")
        let movedOriginalURL = directory.appendingPathComponent("original.bin")
        let destinationURL = directory.appendingPathComponent("destination.bin")
        let replacementData = Data("replacement".utf8)
        try Data("original".utf8).write(to: sourceURL)
        let originalIdentity = try CaptureFileIdentity.existingFile(at: sourceURL)
        try FileManager.default.moveItem(at: sourceURL, to: movedOriginalURL)
        try replacementData.write(to: sourceURL)

        XCTAssertThrowsError(
            try ExclusiveFilePublisher.copyExclusively(
                from: sourceURL,
                to: destinationURL,
                expectedSourceIdentity: originalIdentity
            )
        ) { error in
            XCTAssertEqual(error as? FileOutputError, .sourceFileChanged)
        }

        XCTAssertEqual(try Data(contentsOf: sourceURL), replacementData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testExclusiveCopyDoesNotExposeFinalDestinationUntilCopyCompletes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("source-large.bin")
        let destinationURL = directory.appendingPathComponent("destination-large.bin")
        let sourceData = Data(repeating: 0xA5, count: 256 * 1_024)
        try sourceData.write(to: sourceURL)
        let gate = CopyProgressGate()
        let errorBox = ConcurrentErrorBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            do {
                try ExclusiveFilePublisher.copyExclusively(
                    from: sourceURL,
                    to: destinationURL,
                    copyDidWriteChunk: gate.pauseAfterFirstChunk
                )
            } catch {
                errorBox.store(error)
            }
        }

        XCTAssertEqual(gate.waitUntilPaused(timeout: 2), .success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        gate.resume()
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)

        XCTAssertNil(errorBox.error)
        XCTAssertEqual(try Data(contentsOf: destinationURL), sourceData)
    }

    func testPublisherPreservesReplacementCreatedImmediatelyBeforeSourceRemoval() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("source-race.bin")
        let movedOriginalURL = directory.appendingPathComponent("moved-original.bin")
        let destinationURL = directory.appendingPathComponent("destination-race.bin")
        let originalData = Data("original".utf8)
        let replacementData = Data("replacement".utf8)
        try originalData.write(to: sourceURL)
        let originalIdentity = try CaptureFileIdentity.existingFile(at: sourceURL)

        try ExclusiveFilePublisher.publish(
            from: sourceURL,
            to: destinationURL,
            expectedSourceIdentity: originalIdentity,
            sourceIdentityWasCheckedBeforeRemoval: {
                try FileManager.default.moveItem(at: sourceURL, to: movedOriginalURL)
                try replacementData.write(to: sourceURL)
            }
        )

        XCTAssertEqual(try Data(contentsOf: destinationURL), originalData)
        XCTAssertEqual(try Data(contentsOf: sourceURL), replacementData)
        XCTAssertEqual(try Data(contentsOf: movedOriginalURL), originalData)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains { $0.hasPrefix(".CaptureStudio-Remove-") }
        )
    }

    func testPublisherPreservesReplacementAtFinalPathBeforeIdentityValidation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("source-destination-race.bin")
        let destinationURL = directory.appendingPathComponent("destination-race.bin")
        let movedPublishedURL = directory.appendingPathComponent("moved-published.bin")
        let originalData = Data("original".utf8)
        let replacementData = Data("replacement".utf8)
        try originalData.write(to: sourceURL)
        let originalIdentity = try CaptureFileIdentity.existingFile(at: sourceURL)

        XCTAssertThrowsError(
            try ExclusiveFilePublisher.publish(
                from: sourceURL,
                to: destinationURL,
                expectedSourceIdentity: originalIdentity,
                destinationWasPublished: {
                    try FileManager.default.moveItem(at: destinationURL, to: movedPublishedURL)
                    try replacementData.write(to: destinationURL)
                }
            )
        ) { error in
            XCTAssertEqual(error as? FileOutputError, .sourceFileChanged)
        }

        XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)
        XCTAssertEqual(try Data(contentsOf: destinationURL), replacementData)
        XCTAssertEqual(try Data(contentsOf: movedPublishedURL), originalData)
    }

    func testPublisherKeepsCompletedDestinationWhenSourceCleanupFailsAfterQuarantine() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source-cleanup-failure.bin")
        let destinationURL = directory.appendingPathComponent("destination-cleanup-failure.bin")
        let originalData = Data("original".utf8)
        try originalData.write(to: sourceURL)

        try ExclusiveFilePublisher.publish(
            from: sourceURL,
            to: destinationURL,
            quarantinedSourceWillBeRemoved: {
                throw POSIXError(.EACCES)
            }
        )

        XCTAssertEqual(try Data(contentsOf: destinationURL), originalData)
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains { $0.hasPrefix(".CaptureStudio-Remove-") }
        )
    }

    func testCopyFallbackKeepsCompletedDestinationWhenSourceCleanupFailsAfterQuarantine() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("copy-source-cleanup-failure.bin")
        let destinationURL = directory.appendingPathComponent("copy-destination-cleanup-failure.bin")
        let originalData = Data(repeating: 0x4C, count: 128 * 1_024)
        try originalData.write(to: sourceURL)

        try ExclusiveFilePublisher.copyExclusively(
            from: sourceURL,
            to: destinationURL,
            quarantinedSourceWillBeRemoved: {
                throw POSIXError(.EACCES)
            }
        )

        XCTAssertEqual(try Data(contentsOf: destinationURL), originalData)
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains { $0.hasPrefix(".CaptureStudio-Remove-") }
        )
    }
}

private final class ConcurrentWriteResults: @unchecked Sendable {
    private let lock = NSLock()
    private var storedURLs: [URL] = []
    private var storedErrors: [Error] = []

    var urls: [URL] {
        lock.withLock { storedURLs }
    }

    var errors: [Error] {
        lock.withLock { storedErrors }
    }

    func append(url: URL) {
        lock.withLock { storedURLs.append(url) }
    }

    func append(error: Error) {
        lock.withLock { storedErrors.append(error) }
    }
}

private final class ThreadObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    var mainThreadValues: [Bool] {
        lock.withLock { values }
    }

    func recordCurrentThread() {
        lock.withLock { values.append(Thread.isMainThread) }
    }
}

private final class CopyProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private let paused = DispatchSemaphore(value: 0)
    private let resumeSemaphore = DispatchSemaphore(value: 0)
    private var didPause = false

    func pauseAfterFirstChunk() {
        let shouldPause = lock.withLock { () -> Bool in
            guard !didPause else {
                return false
            }
            didPause = true
            return true
        }
        guard shouldPause else {
            return
        }
        paused.signal()
        resumeSemaphore.wait()
    }

    func waitUntilPaused(timeout: TimeInterval) -> DispatchTimeoutResult {
        paused.wait(timeout: .now() + timeout)
    }

    func resume() {
        resumeSemaphore.signal()
    }
}

private final class ConcurrentErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    var error: Error? {
        lock.withLock { storedError }
    }

    func store(_ error: Error) {
        lock.withLock { storedError = error }
    }
}
