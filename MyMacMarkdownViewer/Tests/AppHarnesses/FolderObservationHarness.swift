import Foundation

@main
struct Harness {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MMV-FSEvents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var callbacks = 0
        var heartbeat = 0
        var longestHeartbeatGap = 0.0
        let heartbeatTask = Task { @MainActor in
            var previous = Date()
            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(10))
                let now = Date()
                longestHeartbeatGap = max(longestHeartbeatGap, now.timeIntervalSince(previous))
                previous = now
                heartbeat += 1
            }
        }
        var watcher: FolderObservation? = FolderObservation(url: root) { callbacks += 1 }
        try await Task.sleep(for: .milliseconds(500))
        try Data("first".utf8).write(to: root.appendingPathComponent("event.txt"), options: .atomic)
        for _ in 0..<30 where callbacks == 0 { try await Task.sleep(for: .milliseconds(100)) }
        guard callbacks > 0 else { fatalError("change event not delivered") }
        watcher?.stop()
        let stoppedCount = callbacks
        try Data("second".utf8).write(to: root.appendingPathComponent("event.txt"), options: .atomic)
        try await Task.sleep(for: .seconds(1))
        guard callbacks == stoppedCount else { fatalError("callback delivered after stop") }
        watcher = nil
        for _ in 0..<50 {
            let transient = FolderObservation(url: root) { callbacks += 1 }
            transient.stop()
        }
        try Data("third".utf8).write(to: root.appendingPathComponent("event.txt"), options: .atomic)
        try await Task.sleep(for: .seconds(1))
        guard callbacks == stoppedCount else { fatalError("callback delivered after repeated stop") }
        _ = await heartbeatTask.value
        guard heartbeat == 100, longestHeartbeatGap < 0.5 else { fatalError("main actor was not responsive") }
        print("PASS callbacks=\(callbacks) heartbeat=\(heartbeat) longestGap=\(longestHeartbeatGap)s")
    }
}
