import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerStoreProgressPresentationTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderProgressPresentation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDirectory)
    }

    @MainActor
    func testMenuValidationDoesNotRepeatedlyDecodeUnchangedLargeClipboard() {
        let clipboard = ProgressPresentationClipboard(
            urls: (0..<2_001).map { tempDirectory.appendingPathComponent("file \($0).txt") }
        )
        let store = ExplorerStore(
            initialURL: tempDirectory,
            settingsStore: ProgressPresentationSettingsStore(),
            directoryWatcher: nil,
            filePasteboardReader: { clipboard.reads += 1; return clipboard.urls },
            filePasteboardChangeCount: { clipboard.changeCount }
        )

        for _ in 0..<100 {
            XCTAssertTrue(store.canPaste)
            XCTAssertTrue(store.isCommandEnabled(.paste))
        }
        XCTAssertEqual(clipboard.reads, 1)

        clipboard.urls = []
        clipboard.changeCount += 1
        XCTAssertFalse(store.canPaste)
        XCTAssertFalse(store.isCommandEnabled(.paste))
        XCTAssertEqual(clipboard.reads, 2)
    }

    @MainActor
    func testBriefPasteCompletesWithoutShowingProgressEvenAfterRevealDeadline() async throws {
        let source = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destination = tempDirectory.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = source.appendingPathComponent("brief.txt")
        try "brief copy".write(to: file, atomically: true, encoding: .utf8)
        let store = ExplorerStore(
            initialURL: destination,
            settingsStore: ProgressPresentationSettingsStore(),
            directoryWatcher: nil,
            filePasteboardReader: { [file] },
            operationProgressRevealDelayNanoseconds: 200_000_000,
            operationProgressAutoDismissNanoseconds: 2_000_000_000
        )

        await store.perform(.paste)

        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("brief.txt"), encoding: .utf8), "brief copy")
        XCTAssertEqual(store.activeOperationProgress?.phase, .completed)
        XCTAssertNil(store.visibleOperationProgress)
        try await Task.sleep(nanoseconds: 260_000_000)
        // The pending reveal must not make an already-finished operation pop into the header.
        XCTAssertNil(store.visibleOperationProgress)
        XCTAssertEqual(store.activeOperationProgress?.phase, .completed)
    }

    @MainActor
    func testLongOperationShowsProgressThenCompletionAndAutoDismisses() async throws {
        let (store, extractor) = try await makeHeldOperationStore()
        let operation = Task { await store.perform(.extractZip) }
        await waitUntilStarted(extractor)
        XCTAssertEqual(store.activeOperationProgress?.phase, .running)
        XCTAssertNil(store.visibleOperationProgress)

        await waitUntilVisible(store)
        XCTAssertEqual(store.visibleOperationProgress?.phase, .running)
        XCTAssertEqual(store.visibleOperationProgress?.isCancellable, true)

        await extractor.finish()
        await operation.value
        XCTAssertEqual(store.visibleOperationProgress?.phase, .completed)
        try await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertNil(store.visibleOperationProgress)
        XCTAssertNil(store.activeOperationProgress)
    }

    @MainActor
    func testDelayedProgressKeepsLongOperationCancellationAvailable() async throws {
        let (store, extractor) = try await makeHeldOperationStore()
        let operation = Task { await store.perform(.extractZip) }
        await waitUntilStarted(extractor)
        await waitUntilVisible(store)

        store.cancelActiveOperation()
        for _ in 0..<200 {
            if store.activeOperationProgress?.phase == .cancelled { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        await extractor.finish()
        await operation.value
        XCTAssertEqual(store.visibleOperationProgress?.phase, .cancelled)
        XCTAssertEqual(store.visibleOperationProgress?.isCancellable, false)
        XCTAssertNil(store.visibleError)

        store.clearCompletedOperationProgress()
        XCTAssertNil(store.visibleOperationProgress)
    }

    @MainActor
    private func makeHeldOperationStore() async throws -> (ExplorerStore, HeldProgressZipExtractor) {
        let file = tempDirectory.appendingPathComponent("held.zip")
        try Data().write(to: file)
        let extractor = HeldProgressZipExtractor()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            settingsStore: ProgressPresentationSettingsStore(),
            directoryWatcher: nil,
            zipExtractor: extractor,
            operationProgressRevealDelayNanoseconds: 200_000_000,
            operationProgressAutoDismissNanoseconds: 100_000_000
        )
        await store.refresh()
        store.updateSelection([file])
        return (store, extractor)
    }

    @MainActor
    private func waitUntilStarted(_ extractor: HeldProgressZipExtractor) async {
        for _ in 0..<500 {
            if await extractor.hasStarted { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("Operation did not start")
    }

    @MainActor
    private func waitUntilVisible(_ store: ExplorerStore) async {
        for _ in 0..<500 {
            if store.visibleOperationProgress != nil { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("Long-running operation progress did not appear")
    }
}

private final class ProgressPresentationSettingsStore: ExplorerSettingsStoring {
    func load() -> ExplorerSettings { ExplorerSettings() }
    func save(_ settings: ExplorerSettings) {}
}

private actor HeldProgressZipExtractor: ZipExtracting {
    private let gate: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private(set) var hasStarted = false

    init() {
        let pair = AsyncStream<Void>.makeStream()
        gate = pair.stream
        continuation = pair.continuation
    }

    func extract(
        _ zipURLs: [URL],
        to destinationFolder: URL,
        progress: FileOperationProgressReporter?
    ) async throws -> FileOperationResult {
        await progress?.update(phase: .running, currentItemName: "held.txt", completedUnitCount: 0, totalUnitCount: 1)
        hasStarted = true
        for await _ in gate { break }
        try await progress?.checkCancellation()
        return FileOperationResult()
    }

    func finish() {
        continuation.finish()
    }
}

@MainActor
private final class ProgressPresentationClipboard {
    var urls: [URL]
    var changeCount = 1
    var reads = 0

    init(urls: [URL]) {
        self.urls = urls
    }
}
