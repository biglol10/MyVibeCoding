import Foundation
import XCTest
@testable import MyMacSearchCore

final class FSEventsWatcherLifecycleTests: XCTestCase {
    @MainActor
    func testStoppingActiveWatcherReturnsWithoutMainActorIsolationFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let queue = DispatchQueue(label: "FSEventsWatcherLifecycleTests")
        let watcher = FSEventsWatcher(latency: 0.01, queue: queue)
        try watcher.start(paths: [directory.path], since: nil) { _ in }

        watcher.stop()
        queue.sync {}
    }
}
