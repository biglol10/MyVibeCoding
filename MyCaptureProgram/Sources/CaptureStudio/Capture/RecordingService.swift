@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

public struct RecordingResult: Equatable, Sendable {
    public let fileURL: URL
    public let createdAt: Date

    public init(fileURL: URL, createdAt: Date = Date()) {
        self.fileURL = fileURL
        self.createdAt = createdAt
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

@MainActor
public final class ScreenCaptureKitRecordingService: RecordingServicing {
    public static let shared = ScreenCaptureKitRecordingService()

    private var activeRecorder: ScreenRecorder?

    public init() {}

    public func recordScreen(selection: CaptureSelection, to outputURL: URL, settings: AppSettings) async throws -> RecordingResult {
        let recorder = ScreenRecorder(selection: selection, outputURL: outputURL, settings: settings)
        activeRecorder = recorder
        defer { activeRecorder = nil }
        return try await recorder.record()
    }

    public func stopRecording() async {
        await activeRecorder?.stop()
    }
}

private final class ScreenRecorder: NSObject, @unchecked Sendable, SCStreamDelegate, SCStreamOutput {
    private let outputURL: URL
    private let settings: AppSettings
    private let selection: CaptureSelection
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
    private var didFinish = false

    init(selection: CaptureSelection, outputURL: URL, settings: AppSettings) {
        self.selection = selection
        self.outputURL = outputURL
        self.settings = settings
        super.init()
        sampleOutputQueue.setSpecific(key: sampleOutputQueueKey, value: ())
    }

    func record() async throws -> RecordingResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) ?? content.displays.first else {
            throw RecordingError.noDisplayAvailable
        }

        let currentProcessID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let excludedWindows = content.windows.filter { window in
            window.owningApplication?.processID == currentProcessID
        }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let geometry = ScreenCaptureOutputGeometry(selection: selection, pointPixelScale: CGFloat(filter.pointPixelScale))
        let videoBitRate = settings.recordingQuality.videoBitRate(
            width: geometry.pixelWidth,
            height: geometry.pixelHeight
        )

        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
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
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleOutputQueue)
        if settings.includeSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleOutputQueue)
        }
        if settings.includeMicrophone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleOutputQueue)
        }

        let durationSeconds = settings.recordingDurationSeconds
        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            recordingTask = Task { [weak self] in
                guard let self else {
                    return
                }
                do {
                    try await stream.startCapture()
                    try await Task.sleep(nanoseconds: UInt64(durationSeconds) * 1_000_000_000)
                    try await stream.stopCapture()
                    finishIfNeeded()
                } catch is CancellationError {
                    return
                } catch {
                    finishWithError(error)
                }
            }
        }
    }

    func stop() async {
        recordingTask?.cancel()
        do {
            try await stream?.stopCapture()
            finishIfNeeded()
        } catch {
            finishWithError(error)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        performOnSampleOutputQueue { [weak self] in
            guard let self else {
                return
            }

            if isUserStoppedStreamError(error) {
                finishIfNeeded()
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
        guard !didFinish else {
            return
        }
        didFinish = true

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        microphoneInput?.markAsFinished()

        guard let writer = assetWriter else {
            finishContinuation?.resume(throwing: RecordingError.writerUnavailable)
            finishContinuation = nil
            return
        }

        if firstVideoTime == nil {
            writer.cancelWriting()
            finishContinuation?.resume(throwing: RecordingError.noVideoFramesCaptured)
            finishContinuation = nil
            return
        }

        if let lastVideoTime {
            writer.endSession(atSourceTime: lastVideoTime)
        } else if let firstVideoTime {
            let requestedDuration = CMTime(
                seconds: Double(settings.recordingDurationSeconds),
                preferredTimescale: 600
            )
            writer.endSession(atSourceTime: firstVideoTime + requestedDuration)
        }

        writer.finishWriting { [outputURL, finishContinuation] in
            if writer.status == .completed {
                finishContinuation?.resume(returning: RecordingResult(fileURL: outputURL))
            } else {
                finishContinuation?.resume(throwing: writer.error ?? RecordingError.writerFailed)
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
        guard !didFinish else {
            return
        }
        didFinish = true
        assetWriter?.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
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
    case noDisplayAvailable
    case cannotAddVideoInput
    case writerUnavailable
    case noVideoFramesCaptured
    case writerFailed
    case stoppedByUser
    case streamFailed(String)

    public var errorDescription: String? {
        switch self {
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
