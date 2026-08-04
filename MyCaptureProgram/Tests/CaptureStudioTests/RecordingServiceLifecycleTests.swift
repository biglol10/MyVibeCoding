import XCTest
@testable import CaptureStudio

final class RecordingServiceLifecycleTests: XCTestCase {
    func testStopRequestedBeforeContinuationIsDeferredUntilSetupCompletes() {
        var lifecycle = RecordingLifecycleState()

        XCTAssertEqual(lifecycle.requestStop(), .waitForSetup)
        XCTAssertTrue(lifecycle.installContinuation())
        XCTAssertTrue(lifecycle.beginFinishing())
        XCTAssertFalse(lifecycle.beginFinishing())
    }

    func testStopRequestedAfterContinuationCanFinishCurrentSession() {
        var lifecycle = RecordingLifecycleState()

        XCTAssertFalse(lifecycle.installContinuation())
        XCTAssertEqual(lifecycle.requestStop(), .finishCurrentSession)
        XCTAssertTrue(lifecycle.beginFinishing())
    }

    func testStopDuringPendingStreamStartWaitsThenStopsExactlyOnce() async {
        let stream = SuspendingCaptureStream()
        let lifecycle = RecordingStreamLifecycle(stream: stream)
        let startTask = Task {
            try await lifecycle.start()
        }
        await stream.waitUntilStartCalled()

        let stopTask = Task {
            await lifecycle.stop()
        }
        while !(await lifecycle.hasStopBeenRequested()) {
            await Task.yield()
        }
        let stopCountBeforeStartFinishes = await stream.stopCallCount
        XCTAssertEqual(stopCountBeforeStartFinishes, 0)

        await stream.finishStart()
        await stopTask.value
        do {
            try await startTask.value
            XCTFail("Expected a user stop while starting")
        } catch {
            XCTAssertEqual(error as? RecordingError, .stoppedByUser)
        }
        let stopCountAfterStartFinishes = await stream.stopCallCount
        XCTAssertEqual(stopCountAfterStartFinishes, 1)

        await lifecycle.stop()
        let stopCountAfterSecondStop = await stream.stopCallCount
        XCTAssertEqual(stopCountAfterSecondStop, 1)
    }

    func testStreamStartFailureStillPerformsTeardownBeforeReturningError() async {
        let stream = SuspendingCaptureStream()
        let lifecycle = RecordingStreamLifecycle(stream: stream)
        let startTask = Task {
            try await lifecycle.start()
        }
        await stream.waitUntilStartCalled()

        await stream.failStart(with: RecordingError.writerFailed)

        do {
            try await startTask.value
            XCTFail("Expected start failure")
        } catch {
            XCTAssertEqual(error as? RecordingError, .writerFailed)
        }
        let stopCount = await stream.stopCallCount
        XCTAssertEqual(stopCount, 1)
    }

    func testSecureOutputWorkspaceDoesNotTouchDestinationBeforePublish() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destinationURL = directory.appendingPathComponent("recording.mp4")
        let workspace = try SecureTemporaryOutputWorkspace(
            fileExtension: "mp4",
            baseDirectory: directory
        )
        defer { workspace.cleanup() }

        try Data("recording".utf8).write(to: workspace.outputURL)

        XCTAssertNotEqual(workspace.outputURL, destinationURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        let permissions = try FileManager.default.attributesOfItem(atPath: workspace.directoryURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o700)
    }

    func testSecureOutputWorkspacePublishCannotOverwriteAReplacement() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destinationURL = directory.appendingPathComponent("recording.mp4")
        let workspace = try SecureTemporaryOutputWorkspace(
            fileExtension: "mp4",
            baseDirectory: directory
        )
        defer { workspace.cleanup() }
        try Data("recording".utf8).write(to: workspace.outputURL)
        try Data("replacement".utf8).write(to: destinationURL)

        XCTAssertThrowsError(try workspace.publish(to: destinationURL)) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .EEXIST)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("replacement".utf8))
        XCTAssertEqual(try Data(contentsOf: workspace.outputURL), Data("recording".utf8))
    }

    @MainActor
    func testServiceRejectsASecondRecordingWhileFirstIsStarting() async {
        let session = SuspendingRecordingSession()
        let service = ScreenCaptureKitRecordingService { _, _, _ in session }
        let selection = recordingSelection()
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let first = Task { @MainActor in
            try await service.recordScreen(selection: selection, to: outputURL, settings: .defaults)
        }
        await session.waitUntilStarted()

        do {
            _ = try await service.recordScreen(
                selection: selection,
                to: outputURL.appendingPathExtension("second"),
                settings: .defaults
            )
            XCTFail("Expected duplicate recording to fail")
        } catch {
            XCTAssertEqual(error as? RecordingError, .recordingAlreadyInProgress)
        }

        await session.finish(returning: RecordingResult(fileURL: outputURL))
        _ = try? await first.value
    }

    @MainActor
    func testServiceForwardsStopToRecorderDuringStartup() async {
        let session = SuspendingRecordingSession()
        let service = ScreenCaptureKitRecordingService { _, _, _ in session }
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let task = Task { @MainActor in
            try await service.recordScreen(
                selection: recordingSelection(),
                to: outputURL,
                settings: .defaults
            )
        }
        await session.waitUntilStarted()

        await service.stopRecording()

        let stopCallCount = await session.stopCallCount
        XCTAssertEqual(stopCallCount, 1)
        do {
            _ = try await task.value
            XCTFail("Expected stopped recording to throw")
        } catch {
            XCTAssertEqual(error as? RecordingError, .stoppedByUser)
        }
    }

    private func recordingSelection() -> CaptureSelection {
        CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            rect: CGRect(x: 0, y: 0, width: 50, height: 50),
            scale: 1
        )
    }
}

private actor SuspendingCaptureStream: RecordingCaptureControlling {
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var didCallStart = false
    private(set) var stopCallCount = 0

    func startCapture() async throws {
        didCallStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
    }

    func stopCapture() async throws {
        stopCallCount += 1
    }

    func waitUntilStartCalled() async {
        if didCallStart {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finishStart() {
        startContinuation?.resume()
        startContinuation = nil
    }

    func failStart(with error: Error) {
        startContinuation?.resume(throwing: error)
        startContinuation = nil
    }
}

private actor SuspendingRecordingSession: RecordingSession {
    private var continuation: CheckedContinuation<RecordingResult, Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStart = false
    private(set) var stopCallCount = 0

    func record() async throws -> RecordingResult {
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func stop() async {
        stopCallCount += 1
        continuation?.resume(throwing: RecordingError.stoppedByUser)
        continuation = nil
    }

    func waitUntilStarted() async {
        if didStart {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish(returning result: RecordingResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
