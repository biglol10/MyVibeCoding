import XCTest
@testable import CaptureStudio

final class CaptureCoordinatorPersonalWorkflowTests: XCTestCase {
    @MainActor
    func testAutoSavedScreenshotAddsHistoryItemWithSmartFilenameMetadata() async throws {
        let appState = AppState()
        let settingsStore = makeSettingsStore("historyScreenshot")
        let historyStore = CaptureHistoryStore(defaults: isolatedDefaults("historyScreenshot"))
        let metadataService = MockCaptureMetadataService(
            context: FileNamingContext(
                applicationName: "Google Chrome",
                windowTitle: "Naver News / Economy"
            )
        )
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockPersonalScreenshotService(),
            fileOutputService: FileOutputService(),
            selectionService: MockPersonalSelectionService(),
            historyStore: historyStore,
            metadataService: metadataService
        )

        await coordinator.startScreenshotCapture()

        let item = try XCTUnwrap(historyStore.items.first)
        let fileURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertEqual(item.fileURL, fileURL)
        XCTAssertEqual(item.kind, .screenshot)
        XCTAssertEqual(item.sourceApplication, "Google Chrome")
        XCTAssertEqual(item.windowTitle, "Naver News / Economy")
        XCTAssertTrue(fileURL.lastPathComponent.contains("Google Chrome"))
        XCTAssertTrue(fileURL.lastPathComponent.contains("Naver News Economy"))
    }

    @MainActor
    func testManualScreenshotSaveAddsHistoryAfterFileExists() async throws {
        let appState = AppState()
        let settingsStore = makeSettingsStore("manualHistoryScreenshot")
        settingsStore.update { settings in
            settings.automaticallySaveScreenshots = false
        }
        let historyStore = CaptureHistoryStore(defaults: isolatedDefaults("manualHistoryScreenshot"))
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockPersonalScreenshotService(),
            fileOutputService: FileOutputService(),
            selectionService: MockPersonalSelectionService(),
            historyStore: historyStore,
            metadataService: MockCaptureMetadataService(
                context: FileNamingContext(applicationName: "Safari", windowTitle: "Receipt")
            )
        )

        await coordinator.startScreenshotCapture()
        XCTAssertTrue(historyStore.items.isEmpty)

        await coordinator.saveCurrentDocument()

        let item = try XCTUnwrap(historyStore.items.first)
        XCTAssertEqual(item.fileURL, appState.currentDocument?.fileURL)
        XCTAssertEqual(item.sourceApplication, "Safari")
    }

    @MainActor
    func testPinCurrentScreenshotUsesRenderedScreenshotData() async {
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: URL(fileURLWithPath: "/tmp/pinned.png"),
                data: Data([0x89, 0x50, 0x4E, 0x47]),
                isDirty: false
            )
        )
        let pinService = MockFloatingPinService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("pin"),
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            floatingPinService: pinService
        )

        await coordinator.pinCurrentScreenshot()

        XCTAssertEqual(pinService.pinnedImages.map(\.data), [Data([0x89, 0x50, 0x4E, 0x47])])
        XCTAssertEqual(pinService.pinnedImages.first?.title, "pinned.png")
        XCTAssertEqual(appState.statusMessage, "Screenshot pinned.")
    }

    @MainActor
    func testTrimmingCurrentRecordingUsesExporterAndUpdatesCurrentDocument() async throws {
        let sourceURL = temporaryFile(name: "source.mp4", data: Data([0x00, 0x00, 0x00, 0x18]))
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .recording,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: sourceURL,
                isDirty: false
            )
        )
        let exporter = MockRecordingExportService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("trim"),
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            recordingExportService: exporter
        )

        await coordinator.trimCurrentRecording(startSeconds: 1, endSeconds: 3)

        let request = try XCTUnwrap(exporter.trimRequests.first)
        XCTAssertEqual(request.sourceURL, sourceURL)
        XCTAssertEqual(request.startSeconds, 1)
        XCTAssertEqual(request.endSeconds, 3)
        XCTAssertEqual(appState.currentDocument?.fileURL, request.outputURL)
        XCTAssertEqual(appState.currentDocument?.isDirty, false)
        XCTAssertEqual(appState.statusMessage, "Recording trimmed.")
    }

    @MainActor
    func testExportCurrentRecordingAsGIFUsesExporterAndLeavesRecordingOpen() async throws {
        let sourceURL = temporaryFile(name: "source-gif.mp4", data: Data([0x00, 0x00, 0x00, 0x18]))
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .recording,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: sourceURL,
                isDirty: false
            )
        )
        let exporter = MockRecordingExportService()
        let revealService = MockPersonalFileRevealService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("gif"),
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            fileRevealService: revealService,
            recordingExportService: exporter
        )

        await coordinator.exportCurrentRecordingAsGIF()

        let request = try XCTUnwrap(exporter.gifRequests.first)
        XCTAssertEqual(request.sourceURL, sourceURL)
        XCTAssertEqual(request.outputURL.pathExtension, "gif")
        XCTAssertEqual(appState.currentDocument?.fileURL, sourceURL)
        XCTAssertEqual(revealService.revealedURLs, [request.outputURL])
        XCTAssertEqual(appState.statusMessage, "GIF exported.")
    }

    @MainActor
    private func makeSettingsStore(_ name: String) -> SettingsStore {
        let store = SettingsStore(defaults: isolatedDefaults("settings-\(name)"))
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCoordinatorPersonalWorkflowTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        store.update { settings in
            settings.screenshotFolderPath = temporaryDirectory.path
            settings.recordingFolderPath = temporaryDirectory.path
            settings.showInFinderAfterSave = false
            settings.copyCapturedImageToClipboard = false
            settings.countdownSeconds = 0
        }
        return store
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CaptureCoordinatorPersonalWorkflowTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func temporaryFile(name: String, data: Data) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCoordinatorPersonalWorkflowTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }
}

private final class MockPersonalScreenshotService: ScreenshotServicing {
    func captureImage(selection: CaptureSelection) async throws -> ScreenshotResult {
        ScreenshotResult(pngData: Data([0x89, 0x50, 0x4E, 0x47]), createdAt: Date(timeIntervalSince1970: 20))
    }
}

private final class MockPersonalSelectionService: SelectionServicing {
    func selectRectangle() async throws -> CaptureSelection {
        CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            rect: CGRect(x: 10, y: 20, width: 300, height: 200),
            scale: 1
        )
    }

    func selectWindow() async throws -> CaptureSelection {
        try await selectRectangle()
    }

    func selectFullScreen() async throws -> CaptureSelection {
        try await selectRectangle()
    }
}

private struct MockCaptureMetadataService: CaptureMetadataServicing {
    let context: FileNamingContext?

    func namingContext(for selection: CaptureSelection) -> FileNamingContext? {
        context
    }
}

private final class MockFloatingPinService: FloatingPinServicing {
    struct PinnedImage: Equatable {
        let data: Data
        let title: String
    }

    var pinnedImages: [PinnedImage] = []

    func pinImage(data: Data, title: String) throws {
        pinnedImages.append(PinnedImage(data: data, title: title))
    }
}

private final class MockRecordingExportService: RecordingExportServicing {
    struct TrimRequest: Equatable {
        let sourceURL: URL
        let startSeconds: Double
        let endSeconds: Double
        let outputURL: URL
    }

    struct GIFRequest: Equatable {
        let sourceURL: URL
        let outputURL: URL
        let maxDurationSeconds: Double
    }

    var trimRequests: [TrimRequest] = []
    var gifRequests: [GIFRequest] = []

    func trimRecording(sourceURL: URL, startSeconds: Double, endSeconds: Double, outputURL: URL) async throws -> URL {
        trimRequests.append(
            TrimRequest(sourceURL: sourceURL, startSeconds: startSeconds, endSeconds: endSeconds, outputURL: outputURL)
        )
        try Data([0x00, 0x00, 0x00, 0x18, 0x54]).write(to: outputURL, options: .atomic)
        return outputURL
    }

    func exportGIF(sourceURL: URL, outputURL: URL, maxDurationSeconds: Double) async throws -> URL {
        gifRequests.append(
            GIFRequest(sourceURL: sourceURL, outputURL: outputURL, maxDurationSeconds: maxDurationSeconds)
        )
        try Data("GIF89a".utf8).write(to: outputURL, options: .atomic)
        return outputURL
    }
}

private final class MockPersonalFileRevealService: FileRevealServicing {
    var revealedURLs: [URL] = []

    func reveal(_ url: URL) {
        revealedURLs.append(url)
    }
}
