@preconcurrency import AVFoundation
import Foundation

public struct PendingRecordingMediaValidator: Sendable {
    private let validate: @Sendable (URL) async -> Bool

    public init() {
        validate = { fileURL in
            let asset = AVURLAsset(url: fileURL)
            do {
                async let playable = asset.load(.isPlayable)
                async let duration = asset.load(.duration)
                async let videoTracks = asset.loadTracks(withMediaType: .video)
                let (isPlayable, loadedDuration, tracks) = try await (playable, duration, videoTracks)
                return isPlayable
                    && !tracks.isEmpty
                    && loadedDuration.seconds.isFinite
                    && loadedDuration.seconds > 0
            } catch {
                return false
            }
        }
    }

    init(validate: @escaping @Sendable (URL) async -> Bool) {
        self.validate = validate
    }

    public func isRecoverableRecording(at fileURL: URL) async -> Bool {
        await validate(fileURL)
    }
}
