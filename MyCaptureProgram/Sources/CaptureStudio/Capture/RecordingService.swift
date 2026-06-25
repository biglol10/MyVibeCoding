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
}

public struct ScreenCaptureKitRecordingService: RecordingServicing {
    public init() {}

    public func recordScreen(selection: CaptureSelection, to outputURL: URL, settings: AppSettings) async throws -> RecordingResult {
        let recorder = ScreenRecorder(selection: selection, outputURL: outputURL, settings: settings)
        return try await recorder.record()
    }
}

@MainActor
private final class ScreenRecorder: NSObject, @preconcurrency SCStreamDelegate, @preconcurrency SCStreamOutput {
    private let outputURL: URL
    private let settings: AppSettings
    private let selection: CaptureSelection
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var stream: SCStream?
    private var firstVideoTime: CMTime?
    private var finishContinuation: CheckedContinuation<RecordingResult, Error>?
    private var didFinish = false

    init(selection: CaptureSelection, outputURL: URL, settings: AppSettings) {
        self.selection = selection
        self.outputURL = outputURL
        self.settings = settings
        super.init()
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
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        if settings.includeSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
        }
        if settings.includeMicrophone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: .main)
        }

        let durationSeconds = settings.recordingDurationSeconds
        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            Task { @MainActor in
                do {
                    try await stream.startCapture()
                    try await Task.sleep(nanoseconds: UInt64(durationSeconds) * 1_000_000_000)
                    try await stream.stopCapture()
                    finishIfNeeded()
                } catch {
                    finishWithError(error)
                }
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        finishWithError(RecordingError.stoppedByUser)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
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
            writer.startWriting()
            writer.startSession(atSourceTime: presentationTime)
        }

        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?) {
        guard firstVideoTime != nil, let input, input.isReadyForMoreMediaData else {
            return
        }

        input.append(sampleBuffer)
    }

    private func finishIfNeeded() {
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
        guard !didFinish else {
            return
        }
        didFinish = true
        assetWriter?.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
    }
}

public enum RecordingError: LocalizedError, Equatable {
    case noDisplayAvailable
    case cannotAddVideoInput
    case writerUnavailable
    case noVideoFramesCaptured
    case writerFailed
    case stoppedByUser

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
        }
    }
}
