import XCTest
@testable import CaptureStudio

@MainActor
final class CaptureCoordinatorEditingTests: XCTestCase {
    @MainActor
    func testHistoryIsNotAddedWhenSavedFileDisappearsDuringThumbnailGeneration() async throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCoordinatorEditingTests-history-race-\(UUID().uuidString)", isDirectory: true)
        let thumbnailDirectory = outputDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let settingsStore = SettingsStore(defaults: isolatedDefaults("historyThumbnailRaceSettings"))
        settingsStore.update {
            $0.screenshotFolderPath = outputDirectory.path
            $0.automaticallySaveScreenshots = true
            $0.copyCapturedImageToClipboard = false
        }
        let historyStore = CaptureHistoryStore(
            defaults: isolatedDefaults("historyThumbnailRace"),
            thumbnailDirectory: thumbnailDirectory
        )
        let encoder = BlockingHistoryThumbnailEncoder()
        let thumbnailService = CaptureHistoryThumbnailService { data in
            encoder.encode(data)
        }
        let appState = AppState()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: EditingMockScreenshotService(),
            selectionService: EditingMockSelectionService(),
            historyStore: historyStore,
            historyThumbnailService: thumbnailService
        )

        let captureTask = Task { @MainActor in
            await coordinator.startScreenshotCapture()
        }
        await encoder.waitUntilEncodingStarted()
        let savedURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        try FileManager.default.removeItem(at: savedURL)
        encoder.finishEncoding()
        await captureTask.value

        XCTAssertTrue(historyStore.items.isEmpty)
    }

    func testSaveCurrentScreenshotUsesRenderedDataWhenLayersExist() async throws {
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: isolatedDefaults("saveRendered"))
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        settingsStore.update { settings in
            settings.screenshotFolderPath = outputDirectory.path
        }
        let original = Data([0x89, 0x50, 0x4E, 0x47, 0x00])
        let rendered = Data([0x89, 0x50, 0x4E, 0x47, 0x99])
        let layer = EditorLayer.redaction(
            RedactionLayer(
                frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
            )
        )
        appState.currentDocument = EditorDocument(kind: .screenshot, createdAt: Date(timeIntervalSince1970: 50), data: original, layers: [layer])
        let renderer = MockImageRenderService(renderedData: rendered)
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: EditingMockScreenshotService(),
            fileOutputService: FileOutputService(),
            imageRenderService: renderer
        )

        await coordinator.saveCurrentDocument()

        let fileURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertEqual(try Data(contentsOf: fileURL), rendered)
        XCTAssertEqual(renderer.renderCallCount, 1)
        XCTAssertEqual(renderer.renderWasOnMainThread, false)
    }

    func testCopyCurrentScreenshotUsesRenderedDataWhenLayersExist() async {
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: isolatedDefaults("copyRendered"))
        let original = Data([0x89, 0x50, 0x4E, 0x47, 0x00])
        let rendered = Data([0x89, 0x50, 0x4E, 0x47, 0x88])
        let layer = EditorLayer.redaction(
            RedactionLayer(
                frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
            )
        )
        appState.currentDocument = EditorDocument(kind: .screenshot, data: original, layers: [layer])
        let renderer = MockImageRenderService(renderedData: rendered)
        let clipboard = EditingMockClipboardService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: EditingMockScreenshotService(),
            imageRenderService: renderer,
            clipboardService: clipboard
        )

        await coordinator.copyCurrentDocument()

        XCTAssertEqual(clipboard.copiedPNGData, rendered)
        XCTAssertEqual(renderer.renderCallCount, 1)
        XCTAssertEqual(renderer.renderWasOnMainThread, false)
    }

    func testSaveKeepsOriginalEditorBaseSoUndoCanRemoveSavedLayer() async throws {
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: isolatedDefaults("savePreservesBase"))
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        settingsStore.update { $0.screenshotFolderPath = outputDirectory.path }
        let original = Data([0x89, 0x50, 0x4E, 0x47, 0x11])
        let rendered = Data([0x89, 0x50, 0x4E, 0x47, 0x22])
        let layer = EditorLayer.redaction(
            RedactionLayer(
                frame: CGRect(x: 1, y: 1, width: 5, height: 5),
                style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
            )
        )
        appState.currentDocument = EditorDocument(
            kind: .screenshot,
            data: original,
            layers: [layer],
            undoStack: [EditorSnapshot(layers: [], selectedLayerID: nil)]
        )
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: EditingMockScreenshotService(),
            imageRenderService: MockImageRenderService(renderedData: rendered)
        )

        await coordinator.saveCurrentDocument()

        XCTAssertEqual(appState.currentDocument?.baseImageData, original)
        XCTAssertEqual(appState.currentDocument?.data, original)
        XCTAssertNil(appState.currentDocument?.renderedImageData)
        XCTAssertEqual(appState.currentDocument?.layers, [layer])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(appState.currentDocument?.fileURL)), rendered)

        EditorViewModel(appState: appState).undo()
        XCTAssertTrue(appState.currentDocument?.layers.isEmpty ?? false)
        XCTAssertEqual(appState.currentDocument?.currentImageData, original)
    }

    func testSaveCompletionDoesNotDiscardEditsAddedWhileRendering() async throws {
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: isolatedDefaults("saveConcurrentEdit"))
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        settingsStore.update { $0.screenshotFolderPath = outputDirectory.path }
        let original = Data([0x89, 0x50, 0x4E, 0x47, 0x31])
        let firstLayer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 1, y: 1, width: 5, height: 5),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )
        let concurrentLayer = EditorLayer.ellipse(
            ShapeLayer(
                frame: CGRect(x: 10, y: 10, width: 4, height: 4),
                style: LayerStyle(strokeColor: .blue, fillColor: .clear, lineWidth: 2)
            )
        )
        appState.currentDocument = EditorDocument(kind: .screenshot, data: original, layers: [firstLayer])
        let renderer = BlockingImageRenderService(renderedData: Data([0x89, 0x50, 0x4E, 0x47, 0x32]))
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: EditingMockScreenshotService(),
            imageRenderService: renderer
        )

        let saveTask = Task { @MainActor in
            await coordinator.saveCurrentDocument()
        }
        await renderer.waitUntilRenderingStarted()
        appState.currentDocument?.layers.append(concurrentLayer)
        appState.currentDocument?.isDirty = true
        renderer.finishRendering()
        await saveTask.value

        XCTAssertEqual(appState.currentDocument?.layers, [firstLayer, concurrentLayer])
        XCTAssertTrue(appState.currentDocument?.isDirty ?? false)
    }

    func testSaveDoesNotCreateFileOrHistoryAfterDocumentIsDeletedDuringRendering() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outputDirectory = rootDirectory.appendingPathComponent("output", isDirectory: true)
        let thumbnailDirectory = rootDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let settingsStore = SettingsStore(defaults: isolatedDefaults("saveDeletedDuringRender"))
        settingsStore.update { $0.screenshotFolderPath = outputDirectory.path }
        let historyStore = CaptureHistoryStore(
            defaults: isolatedDefaults("saveDeletedDuringRenderHistory"),
            thumbnailDirectory: thumbnailDirectory
        )
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 1, y: 1, width: 5, height: 5),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .screenshot,
                data: Data([0x89, 0x50, 0x4E, 0x47, 0x51]),
                layers: [layer]
            )
        )
        let renderer = BlockingImageRenderService(
            renderedData: Data([0x89, 0x50, 0x4E, 0x47, 0x52])
        )
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: EditingMockScreenshotService(),
            imageRenderService: renderer,
            historyStore: historyStore
        )

        let saveTask = Task { @MainActor in
            await coordinator.saveCurrentDocument()
        }
        await renderer.waitUntilRenderingStarted()
        coordinator.deleteCurrentDocument()
        renderer.finishRendering()
        await saveTask.value

        XCTAssertNil(appState.currentDocument)
        XCTAssertEqual(appState.statusMessage, "Screenshot discarded.")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).isEmpty)
        XCTAssertTrue(historyStore.items.isEmpty)
    }

    func testOlderSaveCompletingAfterNewerSaveCannotReplaceLatestSavedState() async throws {
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: isolatedDefaults("saveCompletionOrder"))
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        settingsStore.update { $0.screenshotFolderPath = outputDirectory.path }
        let original = Data([0x89, 0x50, 0x4E, 0x47, 0x41])
        let firstRendered = Data([0x89, 0x50, 0x4E, 0x47, 0x42])
        let latestRendered = Data([0x89, 0x50, 0x4E, 0x47, 0x43])
        let firstLayer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 1, y: 1, width: 5, height: 5),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )
        let latestLayer = EditorLayer.ellipse(
            ShapeLayer(
                frame: CGRect(x: 10, y: 10, width: 4, height: 4),
                style: LayerStyle(strokeColor: .blue, fillColor: .clear, lineWidth: 2)
            )
        )
        appState.currentDocument = EditorDocument(kind: .screenshot, data: original, layers: [firstLayer])
        let renderer = FirstCallBlockingImageRenderService(
            firstRenderedData: firstRendered,
            laterRenderedData: latestRendered
        )
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: EditingMockScreenshotService(),
            imageRenderService: renderer
        )

        let olderSave = Task { @MainActor in
            await coordinator.saveCurrentDocument()
        }
        await renderer.waitUntilFirstRenderStarted()
        appState.currentDocument?.layers.append(latestLayer)
        appState.currentDocument?.isDirty = true

        let latestSave = Task { @MainActor in
            await coordinator.saveCurrentDocument()
        }
        await latestSave.value
        renderer.finishFirstRender()
        await olderSave.value

        let currentDocument = try XCTUnwrap(appState.currentDocument)
        XCTAssertEqual(currentDocument.layers, [firstLayer, latestLayer])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(currentDocument.fileURL)), latestRendered)
        XCTAssertFalse(currentDocument.isDirty)
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CaptureCoordinatorEditingTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class MockImageRenderService: ImageRenderServicing, @unchecked Sendable {
    let renderedData: Data
    var renderCallCount = 0
    var renderWasOnMainThread: Bool?

    init(renderedData: Data) {
        self.renderedData = renderedData
    }

    func renderPNG(basePNGData: Data, layers: [EditorLayer]) throws -> Data {
        renderCallCount += 1
        renderWasOnMainThread = Thread.isMainThread
        return renderedData
    }
}

private final class BlockingImageRenderService: ImageRenderServicing, @unchecked Sendable {
    private let renderedData: Data
    private let lock = NSLock()
    private let resume = DispatchSemaphore(value: 0)
    private var didStart = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    init(renderedData: Data) {
        self.renderedData = renderedData
    }

    func renderPNG(basePNGData: Data, layers: [EditorLayer]) throws -> Data {
        lock.lock()
        didStart = true
        let continuation = startContinuation
        startContinuation = nil
        lock.unlock()
        continuation?.resume()
        resume.wait()
        return renderedData
    }

    func waitUntilRenderingStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if didStart {
                lock.unlock()
                continuation.resume()
            } else {
                startContinuation = continuation
                lock.unlock()
            }
        }
    }

    func finishRendering() {
        resume.signal()
    }
}

private final class FirstCallBlockingImageRenderService: ImageRenderServicing, @unchecked Sendable {
    private let firstRenderedData: Data
    private let laterRenderedData: Data
    private let lock = NSLock()
    private let firstResume = DispatchSemaphore(value: 0)
    private var callCount = 0
    private var firstStartContinuation: CheckedContinuation<Void, Never>?

    init(firstRenderedData: Data, laterRenderedData: Data) {
        self.firstRenderedData = firstRenderedData
        self.laterRenderedData = laterRenderedData
    }

    func renderPNG(basePNGData: Data, layers: [EditorLayer]) throws -> Data {
        lock.lock()
        let callIndex = callCount
        callCount += 1
        let continuation = firstStartContinuation
        if callIndex == 0 {
            firstStartContinuation = nil
        }
        lock.unlock()

        if callIndex == 0 {
            continuation?.resume()
            firstResume.wait()
            return firstRenderedData
        }
        return laterRenderedData
    }

    func waitUntilFirstRenderStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if callCount > 0 {
                lock.unlock()
                continuation.resume()
            } else {
                firstStartContinuation = continuation
                lock.unlock()
            }
        }
    }

    func finishFirstRender() {
        firstResume.signal()
    }
}

private final class EditingMockScreenshotService: ScreenshotServicing {
    func captureImage(selection: CaptureSelection) async throws -> ScreenshotResult {
        ScreenshotResult(pngData: Data([0x89, 0x50, 0x4E, 0x47]), createdAt: Date(timeIntervalSince1970: 20))
    }
}

private final class EditingMockSelectionService: SelectionServicing {
    func selectRectangle() async throws -> CaptureSelection {
        CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            rect: CGRect(x: 0, y: 0, width: 40, height: 40),
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

private final class BlockingHistoryThumbnailEncoder: @unchecked Sendable {
    private let lock = NSLock()
    private let resume = DispatchSemaphore(value: 0)
    private var didStart = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    func encode(_ data: Data) -> Data {
        lock.lock()
        didStart = true
        let continuation = startContinuation
        startContinuation = nil
        lock.unlock()
        continuation?.resume()
        resume.wait()
        return data
    }

    func waitUntilEncodingStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if didStart {
                lock.unlock()
                continuation.resume()
            } else {
                startContinuation = continuation
                lock.unlock()
            }
        }
    }

    func finishEncoding() {
        resume.signal()
    }
}

private final class EditingMockClipboardService: ClipboardServicing {
    var copiedPNGData: Data?
    var copiedText: String?

    func copyPNGData(_ data: Data) {
        copiedPNGData = data
    }

    func copyText(_ text: String) {
        copiedText = text
    }
}
