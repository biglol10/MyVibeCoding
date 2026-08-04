import XCTest
@testable import CaptureStudio

final class CaptureCoordinatorDocumentSafetyTests: XCTestCase {
    @MainActor
    func testScreenshotCancellationPreservesExistingDirtyDocument() async {
        let original = makeDirtyScreenshot()
        let appState = AppState(currentDocument: original)
        let selection = SafetyFailingSelectionService(error: SelectionError.cancelled)
        let coordinator = makeCoordinator(
            appState: appState,
            selectionService: selection,
            replacementDecision: .discard
        )

        await coordinator.startScreenshotCapture()

        XCTAssertEqual(appState.currentDocument, original)
        XCTAssertEqual(appState.statusMessage, "Screenshot cancelled.")
    }

    @MainActor
    func testRecordingCancellationPreservesExistingDirtyDocument() async {
        let original = makeDirtyScreenshot()
        let appState = AppState(captureMode: .record, currentDocument: original)
        let selection = SafetyFailingSelectionService(error: SelectionError.cancelled)
        let coordinator = makeCoordinator(
            appState: appState,
            selectionService: selection,
            replacementDecision: .discard
        )

        await coordinator.startScreenRecording()

        XCTAssertEqual(appState.currentDocument, original)
        XCTAssertEqual(appState.statusMessage, "Recording cancelled.")
    }

    @MainActor
    func testReplacementCancelDoesNotStartSelectionOrChangeDocument() async {
        let original = makeDirtyScreenshot()
        let appState = AppState(currentDocument: original)
        let selection = SafetySelectionService()
        let authorizer = SafetyDocumentReplacementAuthorizer(decision: .cancel)
        let coordinator = makeCoordinator(
            appState: appState,
            selectionService: selection,
            authorizer: authorizer
        )

        await coordinator.startScreenshotCapture()

        XCTAssertEqual(authorizer.requestCount, 1)
        XCTAssertEqual(selection.selectionCallCount, 0)
        XCTAssertEqual(appState.currentDocument, original)
        XCTAssertEqual(appState.statusMessage, "Capture cancelled. Current document was preserved.")
    }

    @MainActor
    func testOpeningHistoryItemCancelPreservesDirtyDocument() async throws {
        let original = makeDirtyScreenshot()
        let appState = AppState(currentDocument: original)
        let authorizer = SafetyDocumentReplacementAuthorizer(decision: .cancel)
        let coordinator = makeCoordinator(
            appState: appState,
            selectionService: SafetySelectionService(),
            authorizer: authorizer
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCoordinatorDocumentSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("history.png")
        try Data("history".utf8).write(to: historyURL)
        let item = CaptureHistoryItem(
            kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: 200),
            fileURL: historyURL,
            title: "History",
            detail: "Screenshot",
            fileIdentity: try CaptureFileIdentity.existingFile(at: historyURL)
        )

        await coordinator.openHistoryItem(item)

        XCTAssertEqual(authorizer.requestCount, 1)
        XCTAssertEqual(appState.currentDocument, original)
        XCTAssertEqual(appState.statusMessage, "History item was not opened. Current document was preserved.")
    }

    @MainActor
    func testOpeningHistoryItemReauthorizesUntilTheCurrentDocumentIsStable() async throws {
        let first = makeDirtyScreenshot()
        let second = makeDirtyScreenshot()
        let latest = makeDirtyScreenshot()
        let appState = AppState(currentDocument: first)
        let authorizer = SafetyReentrantDocumentReplacementAuthorizer(
            appState: appState,
            replacements: [second, latest, nil],
            decisions: [.discard, .discard, .cancel]
        )
        let coordinator = makeCoordinator(
            appState: appState,
            selectionService: SafetySelectionService(),
            authorizer: authorizer
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCoordinatorDocumentSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("history.png")
        try Data("history".utf8).write(to: historyURL)
        let item = CaptureHistoryItem(
            kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: 200),
            fileURL: historyURL,
            title: "History",
            detail: "Screenshot",
            fileIdentity: try CaptureFileIdentity.existingFile(at: historyURL)
        )

        await coordinator.openHistoryItem(item)

        XCTAssertEqual(authorizer.requestCount, 3)
        XCTAssertEqual(appState.currentDocument, latest)
        XCTAssertEqual(appState.statusMessage, "History item was not opened. Current document was preserved.")
    }

    @MainActor
    func testOpeningHistoryItemDiscardReplacesDirtyDocument() async throws {
        let original = makeDirtyScreenshot()
        let appState = AppState(currentDocument: original)
        let authorizer = SafetyDocumentReplacementAuthorizer(decision: .discard)
        let coordinator = makeCoordinator(
            appState: appState,
            selectionService: SafetySelectionService(),
            authorizer: authorizer
        )
        let fixture = try makeHistoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        await coordinator.openHistoryItem(fixture.item)

        XCTAssertEqual(authorizer.requestCount, 1)
        XCTAssertNotEqual(appState.currentDocument?.id, original.id)
        XCTAssertEqual(appState.currentDocument?.fileURL, fixture.item.fileURL)
        XCTAssertEqual(appState.statusMessage, "History item opened.")
    }

    @MainActor
    func testOpeningHistoryItemSavePersistsDirtyDocumentBeforeReplacement() async throws {
        let original = makeDirtyScreenshot()
        let appState = AppState(currentDocument: original)
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCoordinatorDocumentSafetyTests-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let store = makeSettingsStore("history-save")
        store.update {
            $0.screenshotFolderPath = outputDirectory.path
            $0.copyCapturedImageToClipboard = false
        }
        let authorizer = SafetyDocumentReplacementAuthorizer(decision: .save)
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: store,
            screenshotService: SafetyScreenshotService(),
            recordingService: SafetyRecordingService(),
            selectionService: SafetySelectionService(),
            screenCapturePermissionChecker: SafetyPermissionChecker(),
            documentReplacementAuthorizer: authorizer
        )
        let fixture = try makeHistoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        await coordinator.openHistoryItem(fixture.item)

        XCTAssertEqual(authorizer.requestCount, 1)
        XCTAssertEqual(appState.currentDocument?.fileURL, fixture.item.fileURL)
        XCTAssertEqual(appState.statusMessage, "History item opened.")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).count, 1)
    }

    @MainActor
    func testReplacementSavePersistsOldDocumentBeforeStartingSelection() async throws {
        let original = makeDirtyScreenshot()
        let appState = AppState(currentDocument: original)
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let store = makeSettingsStore("replacement-save")
        store.update {
            $0.screenshotFolderPath = outputDirectory.path
            $0.copyCapturedImageToClipboard = false
        }
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: store,
            screenshotService: SafetyScreenshotService(),
            recordingService: SafetyRecordingService(),
            selectionService: SafetyFailingSelectionService(error: SelectionError.cancelled),
            screenCapturePermissionChecker: SafetyPermissionChecker(),
            documentReplacementAuthorizer: SafetyDocumentReplacementAuthorizer(decision: .save)
        )

        await coordinator.startScreenshotCapture()

        XCTAssertEqual(appState.currentDocument?.id, original.id)
        XCTAssertNotNil(appState.currentDocument?.fileURL)
        XCTAssertFalse(appState.currentDocument?.isDirty ?? true)
        XCTAssertEqual(appState.statusMessage, "Screenshot cancelled.")
    }

    @MainActor
    func testConcurrentCaptureRequestsEnterSelectionOnlyOnce() async {
        let appState = AppState()
        let selection = SafetySuspendingSelectionService()
        let coordinator = makeCoordinator(appState: appState, selectionService: selection)

        let first = Task { @MainActor in
            await coordinator.startScreenshotCapture()
        }
        await selection.waitUntilStarted()

        XCTAssertTrue(appState.isCaptureOperationInProgress)
        await coordinator.startScreenshotCapture()

        XCTAssertEqual(selection.selectionCallCount, 1)
        XCTAssertEqual(appState.statusMessage, "Another capture operation is already in progress.")

        selection.cancel()
        await first.value
        XCTAssertFalse(appState.isCaptureOperationInProgress)
    }

    @MainActor
    func testRecordingCompletionDoesNotOverwriteDocumentEditedWhileRecordingWhenReplacementIsCancelled() async {
        let original = makeDirtyScreenshot()
        let appState = AppState(captureMode: .record, currentDocument: original)
        let recordingService = SafetySuspendingRecordingService()
        let authorizer = SafetyDocumentReplacementAuthorizer(decisions: [.discard, .cancel])
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("recording-concurrent-edit"),
            screenshotService: SafetyScreenshotService(),
            recordingService: recordingService,
            selectionService: SafetySelectionService(),
            screenCapturePermissionChecker: SafetyPermissionChecker(),
            documentReplacementAuthorizer: authorizer
        )

        let recordingTask = Task { @MainActor in
            await coordinator.startScreenRecording()
        }
        await recordingService.waitUntilStarted()

        let concurrentLayer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 8, y: 9, width: 20, height: 12),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )
        appState.currentDocument?.layers.append(concurrentLayer)
        appState.currentDocument?.isDirty = true
        let editedDocument = appState.currentDocument

        recordingService.finish()
        await recordingTask.value

        XCTAssertEqual(authorizer.requestCount, 2)
        XCTAssertEqual(appState.currentDocument, editedDocument)
        XCTAssertEqual(appState.statusMessage, "Capture cancelled. Current document was preserved.")
    }

    @MainActor
    private func makeCoordinator(
        appState: AppState,
        selectionService: SelectionServicing,
        replacementDecision: DocumentReplacementDecision = .discard,
        authorizer: DocumentReplacementAuthorizing? = nil
    ) -> CaptureCoordinator {
        CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore(UUID().uuidString),
            screenshotService: SafetyScreenshotService(),
            recordingService: SafetyRecordingService(),
            selectionService: selectionService,
            screenCapturePermissionChecker: SafetyPermissionChecker(),
            documentReplacementAuthorizer: authorizer
                ?? SafetyDocumentReplacementAuthorizer(decision: replacementDecision)
        )
    }

    @MainActor
    private func makeSettingsStore(_ suffix: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: "CaptureCoordinatorDocumentSafetyTests.\(suffix).\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: defaults.volatileDomainNames.first ?? "")
        let store = SettingsStore(defaults: defaults)
        store.update {
            $0.automaticallySaveScreenshots = false
            $0.automaticallySaveRecordings = false
            $0.copyCapturedImageToClipboard = false
            $0.defaultDelaySeconds = 0
            $0.countdownSeconds = 0
        }
        return store
    }

    private func makeDirtyScreenshot() -> EditorDocument {
        EditorDocument(
            id: UUID(),
            kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: 100),
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            isDirty: true
        )
    }

    private func makeHistoryFixture() throws -> (directory: URL, item: CaptureHistoryItem) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCoordinatorDocumentSafetyTests-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let historyURL = directory.appendingPathComponent("history.png")
        try Data("history".utf8).write(to: historyURL)
        return (
            directory,
            CaptureHistoryItem(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 200),
                fileURL: historyURL,
                title: "History",
                detail: "Screenshot",
                fileIdentity: try CaptureFileIdentity.existingFile(at: historyURL)
            )
        )
    }
}

@MainActor
private final class SafetyDocumentReplacementAuthorizer: DocumentReplacementAuthorizing {
    private var decisions: [DocumentReplacementDecision]
    private(set) var requestCount = 0

    init(decision: DocumentReplacementDecision) {
        decisions = [decision]
    }

    init(decisions: [DocumentReplacementDecision]) {
        self.decisions = decisions
    }

    func replacementDecision(for document: EditorDocument) async -> DocumentReplacementDecision {
        let index = min(requestCount, max(0, decisions.count - 1))
        requestCount += 1
        return decisions[index]
    }
}

@MainActor
private final class SafetyReentrantDocumentReplacementAuthorizer: DocumentReplacementAuthorizing {
    private let appState: AppState
    private let replacements: [EditorDocument?]
    private let decisions: [DocumentReplacementDecision]
    private(set) var requestCount = 0

    init(
        appState: AppState,
        replacements: [EditorDocument?],
        decisions: [DocumentReplacementDecision]
    ) {
        self.appState = appState
        self.replacements = replacements
        self.decisions = decisions
    }

    func replacementDecision(for document: EditorDocument) async -> DocumentReplacementDecision {
        let index = min(requestCount, max(0, decisions.count - 1))
        if index < replacements.count, let replacement = replacements[index] {
            appState.currentDocument = replacement
        }
        requestCount += 1
        return decisions[index]
    }
}

@MainActor
private final class SafetySelectionService: SelectionServicing {
    private(set) var selectionCallCount = 0

    func selectRectangle() async throws -> CaptureSelection {
        selectionCallCount += 1
        return CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            rect: CGRect(x: 10, y: 10, width: 40, height: 30),
            scale: 1
        )
    }
}

@MainActor
private final class SafetyFailingSelectionService: SelectionServicing {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func selectRectangle() async throws -> CaptureSelection {
        throw error
    }
}

@MainActor
private final class SafetySuspendingSelectionService: SelectionServicing {
    private(set) var selectionCallCount = 0
    private var selectionContinuation: CheckedContinuation<CaptureSelection, Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func selectRectangle() async throws -> CaptureSelection {
        selectionCallCount += 1
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation in
            selectionContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if selectionCallCount > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func cancel() {
        selectionContinuation?.resume(throwing: SelectionError.cancelled)
        selectionContinuation = nil
    }
}

@MainActor
private final class SafetyScreenshotService: ScreenshotServicing {
    func captureImage(selection: CaptureSelection) async throws -> ScreenshotResult {
        ScreenshotResult(pngData: Data([0x89, 0x50, 0x4E, 0x47]))
    }
}

@MainActor
private final class SafetyRecordingService: RecordingServicing {
    func recordScreen(selection: CaptureSelection, to outputURL: URL, settings: AppSettings) async throws -> RecordingResult {
        RecordingResult(fileURL: outputURL)
    }
}

@MainActor
private final class SafetySuspendingRecordingService: RecordingServicing {
    private var continuation: CheckedContinuation<RecordingResult, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStart = false
    private var outputURL: URL?

    func recordScreen(selection: CaptureSelection, to outputURL: URL, settings: AppSettings) async throws -> RecordingResult {
        self.outputURL = outputURL
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        if didStart {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish() {
        guard let outputURL else {
            return
        }
        continuation?.resume(returning: RecordingResult(fileURL: outputURL))
        continuation = nil
    }
}

private struct SafetyPermissionChecker: ScreenCapturePermissionChecking {
    func hasScreenCaptureAccess() -> Bool { true }
}
