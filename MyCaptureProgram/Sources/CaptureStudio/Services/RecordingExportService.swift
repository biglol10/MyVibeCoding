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
    case cannotCreateExporter
    case exportFailed(String)
    case gifDestinationFailed
    case gifFrameFailed
    case outputFileAlreadyExists

    public var errorDescription: String? {
        switch self {
        case .invalidTimeRange:
            return "Choose a trim end time greater than the start time."
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
            let durationLimit = maxDurationSeconds.map { max(0.2, $0) } ?? assetDurationSeconds
            let duration = max(0.2, min(assetDurationSeconds, durationLimit))
            let frameInterval = 0.2
            let frameCount = max(1, Int(duration / frameInterval))
            guard let destination = CGImageDestinationCreateWithURL(
                workspace.outputURL as CFURL,
                UTType.gif.identifier as CFString,
                frameCount,
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
            for index in 0..<frameCount {
                try Task.checkCancellation()
                let seconds = Double(index) * frameInterval
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                if let generatedImage = try? await generator.image(at: time) {
                    let frameProperties = [
                        kCGImagePropertyGIFDictionary: [
                            kCGImagePropertyGIFDelayTime: frameInterval
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
