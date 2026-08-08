import AppKit
import Foundation
import XCTest
@testable import MyMacFinder

final class FilePreviewThumbnailLoaderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        let root = try XCTUnwrap(tempDirectory)
        try FileManager.default.removeItem(at: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        tempDirectory = nil
    }

    func testThumbnailLoaderCanRunOutsideMainActor() async throws {
        let file = tempDirectory.appendingPathComponent("note.txt")
        try "thumbnail".write(to: file, atomically: true, encoding: .utf8)

        _ = await FilePreviewThumbnailLoader.loadPreviewImage(for: file, scale: 1)
    }

    @MainActor
    func testThumbnailLoaderCanRunFromMainActorWithoutCrashing() async throws {
        let file = tempDirectory.appendingPathComponent("main-actor-note.txt")
        try "thumbnail".write(to: file, atomically: true, encoding: .utf8)

        _ = await FilePreviewThumbnailLoader.loadPreviewImage(for: file, scale: 1)
    }

    func testCancellingLoadCancelsGeneratorRequestExactlyOnceAndReturnsPromptly() async {
        let generator = ControlledThumbnailGenerator()
        let task = Task {
            await FilePreviewThumbnailLoader.loadPreviewImage(
                for: URL(fileURLWithPath: "/tmp/large.pdf"),
                scale: 1,
                generator: generator
            )
        }
        await generator.waitUntilStarted()

        task.cancel()
        task.cancel()
        let result = await promptlyAwait(task)

        XCTAssertNil(result.image)
        XCTAssertEqual(generator.cancelledRequestIDs, generator.startedRequestIDs)
        XCTAssertEqual(generator.cancelledRequestIDs.count, 1)
    }

    func testLateCompletionAfterCancellationIsIgnored() async {
        let generator = ControlledThumbnailGenerator()
        let task = Task {
            await FilePreviewThumbnailLoader.loadPreviewImage(
                for: URL(fileURLWithPath: "/tmp/late-preview.pdf"),
                scale: 1,
                generator: generator
            )
        }
        await generator.waitUntilStarted()

        task.cancel()
        let result = await promptlyAwait(task)
        generator.completeStartedRequests(with: NSImage(size: NSSize(width: 40, height: 40)))

        XCTAssertNil(result.image)
        XCTAssertEqual(generator.cancelledRequestIDs.count, 1)
    }

    private func promptlyAwait(
        _ task: Task<FilePreviewThumbnail, Never>,
        timeout: TimeInterval = 0.5
    ) async -> FilePreviewThumbnail {
        let completed = expectation(description: "Thumbnail load returns after cancellation")
        let recorder = ThumbnailResultRecorder()
        Task {
            recorder.record(await task.value)
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: timeout)
        return recorder.result
    }
}

private final class ControlledThumbnailGenerator: FilePreviewThumbnailGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var startedRequests: [FilePreviewThumbnailRequest] = []
    private var cancelledRequests: [FilePreviewThumbnailRequest] = []
    private var completions: [UUID: @Sendable (NSImage?) -> Void] = [:]
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    var startedRequestIDs: [UUID] {
        lock.withLock { startedRequests.map(\.id) }
    }

    var cancelledRequestIDs: [UUID] {
        lock.withLock { cancelledRequests.map(\.id) }
    }

    func generate(
        _ request: FilePreviewThumbnailRequest,
        completion: @escaping @Sendable (NSImage?) -> Void
    ) {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            startedRequests.append(request)
            completions[request.id] = completion
            defer { startWaiters.removeAll() }
            return startWaiters
        }
        waiters.forEach { $0.resume() }
    }

    func cancel(_ request: FilePreviewThumbnailRequest) {
        lock.withLock {
            cancelledRequests.append(request)
        }
    }

    func waitUntilStarted() async {
        if lock.withLock({ !startedRequests.isEmpty }) {
            return
        }

        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock { () -> Bool in
                if !startedRequests.isEmpty {
                    return true
                }
                startWaiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func completeStartedRequests(with image: NSImage?) {
        let callbacks = lock.withLock {
            defer { completions.removeAll() }
            return Array(completions.values)
        }
        callbacks.forEach { $0(image) }
    }
}

private final class ThumbnailResultRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedResult: FilePreviewThumbnail?

    var result: FilePreviewThumbnail {
        lock.withLock {
            guard let recordedResult else {
                XCTFail("Expected the thumbnail task to finish before reading its result")
                return FilePreviewThumbnail(image: nil)
            }
            return recordedResult
        }
    }

    func record(_ result: FilePreviewThumbnail) {
        lock.withLock {
            recordedResult = result
        }
    }
}
