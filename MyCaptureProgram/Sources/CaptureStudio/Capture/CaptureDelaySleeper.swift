import Foundation

@MainActor
public protocol CaptureDelaySleeping {
    func sleep(seconds: Int) async throws
}

public struct TaskCaptureDelaySleeper: CaptureDelaySleeping {
    public init() {}

    public func sleep(seconds: Int) async throws {
        let clampedSeconds = max(0, seconds)
        guard clampedSeconds > 0 else {
            return
        }

        try await Task.sleep(nanoseconds: UInt64(clampedSeconds) * 1_000_000_000)
    }
}
