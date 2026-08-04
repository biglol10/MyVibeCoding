@preconcurrency import AVFoundation
import CoreMedia
import Darwin
import Foundation
@preconcurrency import ScreenCaptureKit

public struct RecordingResult: Equatable, Sendable {
    public let fileURL: URL
    public let createdAt: Date
    public let fileIdentity: CaptureFileIdentity?

    public init(
        fileURL: URL,
        createdAt: Date = Date(),
        fileIdentity: CaptureFileIdentity? = nil
    ) {
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.fileIdentity = fileIdentity ?? (try? CaptureFileIdentity.existingFile(at: fileURL))
    }
}

@MainActor
public protocol RecordingServicing {
    func recordScreen(selection: CaptureSelection, to outputURL: URL, settings: AppSettings) async throws -> RecordingResult
    func stopRecording() async
}

public extension RecordingServicing {
    func stopRecording() async {}
}

protocol RecordingSession: AnyObject, Sendable {
    func record() async throws -> RecordingResult
    func stop() async
}

enum RecordingStopDisposition: Equatable {
    case waitForSetup
    case finishCurrentSession
}

struct RecordingLifecycleState {
    private(set) var stopRequested = false
    private(set) var continuationInstalled = false
    private(set) var didFinish = false

    mutating func requestStop() -> RecordingStopDisposition {
        stopRequested = true
        return continuationInstalled ? .finishCurrentSession : .waitForSetup
    }

    mutating func installContinuation() -> Bool {
        continuationInstalled = true
        return stopRequested
    }

    mutating func beginFinishing() -> Bool {
        guard continuationInstalled, !didFinish else {
            return false
        }
        didFinish = true
        return true
    }
}

protocol RecordingCaptureControlling: Sendable {
    func startCapture() async throws
    func stopCapture() async throws
}

final class ScreenCaptureStreamController: RecordingCaptureControlling, @unchecked Sendable {
    private let stream: SCStream

    init(stream: SCStream) {
        self.stream = stream
    }

    func startCapture() async throws {
        try await stream.startCapture()
    }

    func stopCapture() async throws {
        try await stream.stopCapture()
    }
}

actor RecordingStreamLifecycle {
    private let stream: any RecordingCaptureControlling
    private var startTask: Task<Void, Error>?
    private var stopTask: Task<Void, Never>?
    private var stopRequested = false

    init(stream: any RecordingCaptureControlling) {
        self.stream = stream
    }

    func hasStopBeenRequested() -> Bool {
        stopRequested
    }

    func start() async throws {
        guard !stopRequested else {
            throw RecordingError.stoppedByUser
        }

        let task: Task<Void, Error>
        if let startTask {
            task = startTask
        } else {
            let stream = self.stream
            task = Task {
                try await stream.startCapture()
            }
            startTask = task
        }

        do {
            try await task.value
        } catch {
            await stop()
            throw error
        }

        if stopRequested {
            await stop()
            throw RecordingError.stoppedByUser
        }
    }

    func stop() async {
        stopRequested = true
        if let stopTask {
            await stopTask.value
            return
        }

        let stream = self.stream
        let startTask = self.startTask
        let task = Task<Void, Never> {
            if let startTask {
                _ = try? await startTask.value
            }
            try? await stream.stopCapture()
        }
        stopTask = task
        await task.value
    }
}

@MainActor
public final class ScreenCaptureKitRecordingService: RecordingServicing {
    public static let shared = ScreenCaptureKitRecordingService()

    typealias RecordingSessionFactory = @MainActor (
        _ selection: CaptureSelection,
        _ outputURL: URL,
        _ settings: AppSettings
    ) -> any RecordingSession

    private var activeRecorder: (any RecordingSession)?
    private let makeRecorder: RecordingSessionFactory

    public convenience init() {
        self.init { selection, outputURL, settings in
            ScreenRecorder(selection: selection, outputURL: outputURL, settings: settings)
        }
    }

    init(_ makeRecorder: @escaping RecordingSessionFactory) {
        self.makeRecorder = makeRecorder
    }

    public func recordScreen(selection: CaptureSelection, to outputURL: URL, settings: AppSettings) async throws -> RecordingResult {
        guard activeRecorder == nil else {
            throw RecordingError.recordingAlreadyInProgress
        }

        let recorder = makeRecorder(selection, outputURL, settings)
        activeRecorder = recorder
        defer {
            if activeRecorder === recorder {
                activeRecorder = nil
            }
        }
        return try await recorder.record()
    }

    public func stopRecording() async {
        await activeRecorder?.stop()
    }
}

private final class ScreenRecorder: NSObject, @unchecked Sendable, RecordingSession, SCStreamDelegate, SCStreamOutput {
    private let outputURL: URL
    private let settings: AppSettings
    private let selection: CaptureSelection
    private let durationSeconds: Int
    private let sampleOutputQueue = DispatchQueue(label: "com.capturestudio.recording.sample-output", qos: .userInitiated)
    private let sampleOutputQueueKey = DispatchSpecificKey<Void>()
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var stream: SCStream?
    private var firstVideoTime: CMTime?
    private var lastVideoTime: CMTime?
    private var finishContinuation: CheckedContinuation<RecordingResult, Error>?
    private var recordingTask: Task<Void, Never>?
    private var streamLifecycle: RecordingStreamLifecycle?
    private var lifecycle = RecordingLifecycleState()
    private var outputWorkspace: SecureTemporaryOutputWorkspace?

    init(selection: CaptureSelection, outputURL: URL, settings: AppSettings) {
        self.selection = selection
        self.outputURL = outputURL
        self.settings = settings
        self.durationSeconds = min(max(settings.recordingDurationSeconds, 1), 120)
        super.init()
        sampleOutputQueue.setSpecific(key: sampleOutputQueueKey, value: ())
    }

    func record() async throws -> RecordingResult {
        var didInstallContinuation = false
        defer {
            if !didInstallContinuation {
                assetWriter?.cancelWriting()
                cleanupOutputWorkspace()
            }
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) ?? content.displays.first else {
            throw RecordingError.noDisplayAvailable
        }

        let currentProcessID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let currentBundleIdentifier = Bundle.main.bundleIdentifier
        let excludedApplications = content.applications.filter { application in
            ScreenCaptureApplicationMatcher.matches(
                applicationProcessID: application.processID,
                applicationBundleIdentifier: application.bundleIdentifier,
                currentProcessID: currentProcessID,
                currentBundleIdentifier: currentBundleIdentifier
            )
        }
        guard !excludedApplications.isEmpty else {
            throw ScreenCaptureContentFilterError.currentApplicationUnavailable
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        let geometry = ScreenCaptureOutputGeometry(selection: selection, pointPixelScale: CGFloat(filter.pointPixelScale))
        let videoBitRate = settings.recordingQuality.videoBitRate(
            width: geometry.pixelWidth,
            height: geometry.pixelHeight
        )

        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw RecordingError.outputFileAlreadyExists
        }

        let outputWorkspace = try SecureTemporaryOutputWorkspace(fileExtension: "mp4")
        self.outputWorkspace = outputWorkspace
        let writer = try AVAssetWriter(outputURL: outputWorkspace.outputURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: geometry.pixelWidth,
                AVVideoHeightKey: geometry.pixelHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: videoBitRate
                ]
            ]
        )
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else {
            throw RecordingError.cannotAddVideoInput
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if settings.includeSystemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        var microphoneInput: AVAssetWriterInput?
        if settings.includeMicrophone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                microphoneInput = input
            }
        }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = geometry.sourceRectInPoints
        configuration.width = geometry.pixelWidth
        configuration.height = geometry.pixelHeight
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = settings.showCursorInRecordings
        configuration.capturesAudio = settings.includeSystemAudio
        configuration.captureMicrophone = settings.includeMicrophone
        configuration.excludesCurrentProcessAudio = true

        self.assetWriter = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.microphoneInput = microphoneInput

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream
        let streamLifecycle = RecordingStreamLifecycle(
            stream: ScreenCaptureStreamController(stream: stream)
        )
        self.streamLifecycle = streamLifecycle
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleOutputQueue)
        if settings.includeSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleOutputQueue)
        }
        if settings.includeMicrophone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleOutputQueue)
        }

        didInstallContinuation = true
        return try await withCheckedThrowingContinuation { continuation in
            performOnSampleOutputQueue { [weak self] in
                guard let self else {
                    continuation.resume(throwing: RecordingError.writerUnavailable)
                    return
                }

                finishContinuation = continuation
                if lifecycle.installContinuation() {
                    finishWithErrorOnSampleOutputQueue(.stoppedByUser)
                    return
                }

                recordingTask = Task { [weak self] in
                    guard let self else {
                        return
                    }
                    do {
                        try await streamLifecycle.start()
                        try await Task.sleep(nanoseconds: UInt64(durationSeconds) * 1_000_000_000)
                        await streamLifecycle.stop()
                        finishIfNeeded()
                    } catch is CancellationError {
                        await streamLifecycle.stop()
                        finishAfterUserStop()
                    } catch RecordingError.stoppedByUser {
                        await streamLifecycle.stop()
                        finishAfterUserStop()
                    } catch {
                        await streamLifecycle.stop()
                        finishWithError(error)
                    }
                }
            }
        }
    }

    func stop() async {
        let stopContext = await withCheckedContinuation { continuation in
            performOnSampleOutputQueue { [weak self] in
                guard let self else {
                    continuation.resume(returning: (
                        RecordingStopDisposition.waitForSetup,
                        Optional<RecordingStreamLifecycle>.none,
                        Optional<Task<Void, Never>>.none
                    ))
                    return
                }
                let disposition = lifecycle.requestStop()
                recordingTask?.cancel()
                continuation.resume(returning: (disposition, streamLifecycle, recordingTask))
            }
        }

        guard stopContext.0 == .finishCurrentSession else {
            return
        }

        await stopContext.1?.stop()
        await stopContext.2?.value
        finishAfterUserStop()
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        performOnSampleOutputQueue { [weak self] in
            guard let self else {
                return
            }

            if isUserStoppedStreamError(error) {
                _ = lifecycle.requestStop()
                recordingTask?.cancel()
                let streamLifecycle = self.streamLifecycle
                Task { [self] in
                    await streamLifecycle?.stop()
                    finishAfterUserStop()
                }
                return
            }

            finishWithError(RecordingError.streamFailed(error.localizedDescription))
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        handleSampleBuffer(sampleBuffer, outputType: outputType)
    }

    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer, outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else {
            return
        }

        switch outputType {
        case .screen:
            appendVideo(sampleBuffer)
        case .audio:
            appendAudio(sampleBuffer, to: audioInput)
        case .microphone:
            appendAudio(sampleBuffer, to: microphoneInput)
        @unknown default:
            break
        }
    }

    private func performOnSampleOutputQueue(_ action: @escaping @Sendable () -> Void) {
        if DispatchQueue.getSpecific(key: sampleOutputQueueKey) != nil {
            action()
        } else {
            sampleOutputQueue.async(execute: action)
        }
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let writer = assetWriter, let videoInput else {
            return
        }
        guard ScreenCaptureFrameValidator.isWritableVideoFrame(sampleBuffer) else {
            return
        }

        let presentationTime = sampleBuffer.presentationTimeStamp
        if firstVideoTime == nil {
            firstVideoTime = presentationTime
            guard writer.startWriting() else {
                finishWithError(writer.error ?? RecordingError.writerFailed)
                return
            }
            writer.startSession(atSourceTime: presentationTime)
        }

        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
            lastVideoTime = presentationTime
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?) {
        guard firstVideoTime != nil, let input, input.isReadyForMoreMediaData else {
            return
        }

        input.append(sampleBuffer)
    }

    private func finishIfNeeded() {
        performOnSampleOutputQueue { [weak self] in
            self?.finishIfNeededOnSampleOutputQueue()
        }
    }

    private func finishIfNeededOnSampleOutputQueue() {
        guard lifecycle.beginFinishing() else {
            return
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        microphoneInput?.markAsFinished()

        guard let writer = assetWriter else {
            cleanupOutputWorkspace()
            finishContinuation?.resume(throwing: RecordingError.writerUnavailable)
            finishContinuation = nil
            return
        }

        if firstVideoTime == nil {
            writer.cancelWriting()
            cleanupOutputWorkspace()
            finishContinuation?.resume(throwing: RecordingError.noVideoFramesCaptured)
            finishContinuation = nil
            return
        }

        if let lastVideoTime {
            writer.endSession(atSourceTime: lastVideoTime)
        } else if let firstVideoTime {
            let requestedDuration = CMTime(
                seconds: Double(durationSeconds),
                preferredTimescale: 600
            )
            writer.endSession(atSourceTime: firstVideoTime + requestedDuration)
        }

        let continuation = finishContinuation
        writer.finishWriting { [weak self, outputURL] in
            guard let self else {
                continuation?.resume(throwing: RecordingError.writerUnavailable)
                return
            }
            self.performOnSampleOutputQueue {
                if writer.status == .completed {
                    do {
                        guard let outputWorkspace = self.outputWorkspace else {
                            throw RecordingError.writerUnavailable
                        }
                        try outputWorkspace.publish(to: outputURL)
                        self.outputWorkspace = nil
                        continuation?.resume(
                            returning: RecordingResult(
                                fileURL: outputURL,
                                fileIdentity: try? CaptureFileIdentity.existingFile(at: outputURL)
                            )
                        )
                    } catch {
                        self.cleanupOutputWorkspace()
                        continuation?.resume(throwing: self.recordingError(forPublicationError: error))
                    }
                } else {
                    self.cleanupOutputWorkspace()
                    continuation?.resume(throwing: writer.error ?? RecordingError.writerFailed)
                }
            }
        }
        finishContinuation = nil
    }

    private func finishWithError(_ error: Error) {
        let recordingError = normalizedRecordingError(error)
        performOnSampleOutputQueue { [weak self] in
            self?.finishWithErrorOnSampleOutputQueue(recordingError)
        }
    }

    private func finishWithErrorOnSampleOutputQueue(_ error: RecordingError) {
        guard lifecycle.beginFinishing() else {
            return
        }
        recordingTask?.cancel()
        assetWriter?.cancelWriting()
        let streamLifecycle = self.streamLifecycle
        let continuation = finishContinuation
        finishContinuation = nil
        Task { [self] in
            await streamLifecycle?.stop()
            performOnSampleOutputQueue { [self] in
                cleanupOutputWorkspace()
                continuation?.resume(throwing: error)
            }
        }
    }

    private func finishAfterUserStop() {
        performOnSampleOutputQueue { [weak self] in
            guard let self else {
                return
            }
            if firstVideoTime == nil {
                finishWithErrorOnSampleOutputQueue(.stoppedByUser)
            } else {
                finishIfNeededOnSampleOutputQueue()
            }
        }
    }

    private func cleanupOutputWorkspace() {
        outputWorkspace?.cleanup()
        outputWorkspace = nil
    }

    private func recordingError(forPublicationError error: Error) -> RecordingError {
        if (error as? POSIXError)?.code == .EEXIST {
            return .outputFileAlreadyExists
        }
        if let recordingError = error as? RecordingError {
            return recordingError
        }
        return .streamFailed(error.localizedDescription)
    }

    private func normalizedRecordingError(_ error: Error) -> RecordingError {
        if let recordingError = error as? RecordingError {
            return recordingError
        }

        return RecordingError.streamFailed(error.localizedDescription)
    }

    private func isUserStoppedStreamError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain
            && nsError.code == SCStreamError.Code.userStopped.rawValue
    }
}

public enum RecordingError: LocalizedError, Equatable, Sendable {
    case recordingAlreadyInProgress
    case outputFileAlreadyExists
    case noDisplayAvailable
    case cannotAddVideoInput
    case writerUnavailable
    case noVideoFramesCaptured
    case writerFailed
    case stoppedByUser
    case streamFailed(String)

    public var errorDescription: String? {
        switch self {
        case .recordingAlreadyInProgress:
            return "A recording is already in progress."
        case .outputFileAlreadyExists:
            return "The recording output file already exists."
        case .noDisplayAvailable:
            return "No display is available for recording."
        case .cannotAddVideoInput:
            return "The recording writer could not add a video input."
        case .writerUnavailable:
            return "The recording writer is unavailable."
        case .noVideoFramesCaptured:
            return "No video frames were captured."
        case .writerFailed:
            return "The recording writer failed."
        case .stoppedByUser:
            return "The recording was stopped."
        case .streamFailed(let reason):
            return "Recording stopped unexpectedly: \(reason)"
        }
    }
}
