@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
public protocol RecordingExportServicing {
    func trimRecording(sourceURL: URL, startSeconds: Double, endSeconds: Double?, outputURL: URL) async throws -> RecordingExportResult
    func exportGIF(sourceURL: URL, outputURL: URL, maxDurationSeconds: Double?) async throws -> RecordingExportResult
}

struct RecordingTrimRange: Equatable, Sendable {
    let startSeconds: Double
    let endSeconds: Double
}

enum RecordingTrimRangeResolver {
    static func resolve(
        startSeconds: Double,
        endSeconds: Double?,
        assetDurationSeconds: Double
    ) throws -> RecordingTrimRange {
        guard startSeconds.isFinite,
              startSeconds >= 0,
              assetDurationSeconds.isFinite,
              assetDurationSeconds > 0
        else {
            throw RecordingExportError.invalidTimeRange
        }

        if let endSeconds, !endSeconds.isFinite {
            throw RecordingExportError.invalidTimeRange
        }
        let resolvedEnd = min(endSeconds ?? assetDurationSeconds, assetDurationSeconds)
        guard resolvedEnd > startSeconds else {
            throw RecordingExportError.invalidTimeRange
        }

        return RecordingTrimRange(startSeconds: startSeconds, endSeconds: resolvedEnd)
    }
}

struct RecordingGIFPlan: Equatable, Sendable {
    let durationSeconds: Double
    let frameIntervalSeconds: Double
    let frameCount: Int
}

enum RecordingGIFPlanResolver {
    private static let maximumFrameCount = 3_600

    static func resolve(
        assetDurationSeconds: Double,
        maxDurationSeconds: Double?
    ) throws -> RecordingGIFPlan {
        guard assetDurationSeconds.isFinite, assetDurationSeconds > 0 else {
            throw RecordingExportError.invalidMediaDuration
        }
        if let maxDurationSeconds {
            guard maxDurationSeconds.isFinite, maxDurationSeconds > 0 else {
                throw RecordingExportError.invalidGIFDurationLimit
            }
        }

        let duration = min(assetDurationSeconds, maxDurationSeconds ?? assetDurationSeconds)
        let frameInterval = 0.2
        let rawFrameCount = ceil(duration / frameInterval)
        guard rawFrameCount.isFinite else {
            throw RecordingExportError.invalidMediaDuration
        }
        guard rawFrameCount <= Double(maximumFrameCount) else {
            throw RecordingExportError.gifTooLong
        }
        return RecordingGIFPlan(
            durationSeconds: duration,
            frameIntervalSeconds: frameInterval,
            frameCount: max(1, Int(rawFrameCount))
        )
    }
}

public struct RecordingExportResult: Equatable, Sendable {
    public let fileURL: URL
    public let fileIdentity: CaptureFileIdentity?

    public init(fileURL: URL, fileIdentity: CaptureFileIdentity? = nil) {
        self.fileURL = fileURL
        self.fileIdentity = fileIdentity ?? (try? CaptureFileIdentity.existingFile(at: fileURL))
    }
}

public enum RecordingExportError: LocalizedError, Equatable {
    case invalidTimeRange
    case invalidMediaDuration
    case invalidGIFDurationLimit
    case gifTooLong
    case cannotCreateExporter
    case exportFailed(String)
    case gifDestinationFailed
    case gifFrameFailed
    case outputFileAlreadyExists

    public var errorDescription: String? {
        switch self {
        case .invalidTimeRange:
            return "Choose a trim end time greater than the start time."
        case .invalidMediaDuration:
            return "The recording duration could not be read."
        case .invalidGIFDurationLimit:
            return "The GIF duration limit is invalid."
        case .gifTooLong:
            return "The recording is too long to export as a GIF."
        case .cannotCreateExporter:
            return "The recording could not be prepared for export."
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .gifDestinationFailed:
            return "The GIF file could not be created."
        case .gifFrameFailed:
            return "The recording did not produce GIF frames."
        case .outputFileAlreadyExists:
            return "The export output file already exists."
        }
    }
}

public struct AVFoundationRecordingExportService: RecordingExportServicing {
    public init() {}

    public func trimRecording(
        sourceURL: URL,
        startSeconds: Double,
        endSeconds: Double?,
        outputURL: URL
    ) async throws -> RecordingExportResult {
        let asset = AVURLAsset(url: sourceURL)
        let assetDuration = try await asset.load(.duration)
        let rangeSeconds = try RecordingTrimRangeResolver.resolve(
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            assetDurationSeconds: CMTimeGetSeconds(assetDuration)
        )
        let start = CMTime(seconds: rangeSeconds.startSeconds, preferredTimescale: 600)
        let end = CMTime(seconds: rangeSeconds.endSeconds, preferredTimescale: 600)
        let range = CMTimeRange(start: start, end: end)

        let workspace = try SecureTemporaryOutputWorkspace(fileExtension: "mp4")
        defer { workspace.cleanup() }
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw RecordingExportError.cannotCreateExporter
        }
        exportSession.outputURL = workspace.outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = range

        do {
            try await exportSession.export(to: workspace.outputURL, as: .mp4)
            try workspace.publish(to: outputURL)
            return RecordingExportResult(fileURL: outputURL)
        } catch {
            if (error as? POSIXError)?.code == .EEXIST {
                throw RecordingExportError.outputFileAlreadyExists
            }
            throw RecordingExportError.exportFailed(error.localizedDescription)
        }
    }

    public func exportGIF(
        sourceURL: URL,
        outputURL: URL,
        maxDurationSeconds: Double?
    ) async throws -> RecordingExportResult {
        let workspace = try SecureTemporaryOutputWorkspace(fileExtension: "gif")
        defer { workspace.cleanup() }
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: sourceURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 960, height: 960)

            let assetDuration = try await asset.load(.duration)
            let assetDurationSeconds = CMTimeGetSeconds(assetDuration)
            let plan = try RecordingGIFPlanResolver.resolve(
                assetDurationSeconds: assetDurationSeconds,
                maxDurationSeconds: maxDurationSeconds
            )
            guard let destination = CGImageDestinationCreateWithURL(
                workspace.outputURL as CFURL,
                UTType.gif.identifier as CFString,
                plan.frameCount,
                nil
            ) else {
                throw RecordingExportError.gifDestinationFailed
            }

            let gifProperties = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0
                ]
            ] as CFDictionary
            CGImageDestinationSetProperties(destination, gifProperties)

            var didAddFrame = false
            for index in 0..<plan.frameCount {
                try Task.checkCancellation()
                let seconds = Double(index) * plan.frameIntervalSeconds
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                if let generatedImage = try? await generator.image(at: time) {
                    let frameProperties = [
                        kCGImagePropertyGIFDictionary: [
                            kCGImagePropertyGIFDelayTime: plan.frameIntervalSeconds
                        ]
                    ] as CFDictionary
                    CGImageDestinationAddImage(destination, generatedImage.image, frameProperties)
                    didAddFrame = true
                }
            }

            guard didAddFrame else {
                throw RecordingExportError.gifFrameFailed
            }
            guard CGImageDestinationFinalize(destination) else {
                throw RecordingExportError.gifDestinationFailed
            }
        }.value

        do {
            try workspace.publish(to: outputURL)
            return RecordingExportResult(fileURL: outputURL)
        } catch {
            if (error as? POSIXError)?.code == .EEXIST {
                throw RecordingExportError.outputFileAlreadyExists
            }
            throw error
        }
    }
}
