@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
public protocol RecordingExportServicing {
    func trimRecording(sourceURL: URL, startSeconds: Double, endSeconds: Double, outputURL: URL) async throws -> URL
    func exportGIF(sourceURL: URL, outputURL: URL, maxDurationSeconds: Double?) async throws -> URL
}

public enum RecordingExportError: LocalizedError, Equatable {
    case invalidTimeRange
    case cannotCreateExporter
    case exportFailed(String)
    case gifDestinationFailed
    case gifFrameFailed

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
        }
    }
}

public struct AVFoundationRecordingExportService: RecordingExportServicing {
    public init() {}

    public func trimRecording(sourceURL: URL, startSeconds: Double, endSeconds: Double, outputURL: URL) async throws -> URL {
        guard endSeconds > startSeconds, startSeconds >= 0 else {
            throw RecordingExportError.invalidTimeRange
        }

        let asset = AVURLAsset(url: sourceURL)
        let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
        let end = CMTime(seconds: endSeconds, preferredTimescale: 600)
        let range = CMTimeRange(start: start, end: end)

        try? FileManager.default.removeItem(at: outputURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw RecordingExportError.cannotCreateExporter
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = range

        do {
            try await exportSession.export(to: outputURL, as: .mp4)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw RecordingExportError.exportFailed(error.localizedDescription)
        }
    }

    public func exportGIF(sourceURL: URL, outputURL: URL, maxDurationSeconds: Double?) async throws -> URL {
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
            try? FileManager.default.removeItem(at: outputURL)

            do {
                guard let destination = CGImageDestinationCreateWithURL(
                    outputURL as CFURL,
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
                    let seconds = Double(index) * frameInterval
                    let time = CMTime(seconds: seconds, preferredTimescale: 600)
                    if let image = try? generator.copyCGImage(at: time, actualTime: nil) {
                        let frameProperties = [
                            kCGImagePropertyGIFDictionary: [
                                kCGImagePropertyGIFDelayTime: frameInterval
                            ]
                        ] as CFDictionary
                        CGImageDestinationAddImage(destination, image, frameProperties)
                        didAddFrame = true
                    }
                }

                guard didAddFrame else {
                    throw RecordingExportError.gifFrameFailed
                }
                guard CGImageDestinationFinalize(destination) else {
                    throw RecordingExportError.gifDestinationFailed
                }
                return outputURL
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
        }.value
    }
}
