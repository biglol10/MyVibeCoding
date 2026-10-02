import XCTest
@testable import PaneHarbor

final class FileOperationProgressReporterTests: XCTestCase {
    func testFrequentProgressUpdatesAreCoalescedWithoutLosingFinalCounts() async {
        let recorder = ProgressRecorder()
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .copy, title: "Copying"),
            minimumUpdateInterval: .seconds(60),
            onUpdate: { await recorder.append($0) }
        )
        await reporter.update(phase: .running, completedUnitCount: 0, totalUnitCount: 1_000, completedBytes: 0, totalBytes: 1_000)
        for bytes in 1...1_000 {
            await reporter.update(currentItemName: "\(bytes).txt", completedUnitCount: bytes, completedBytes: Int64(bytes))
        }
        let current = await reporter.currentSnapshot
        let intermediate = await recorder.snapshots
        XCTAssertEqual(current.completedBytes, 1_000)
        XCTAssertEqual(current.completedUnitCount, 1_000)
        XCTAssertEqual(intermediate.count, 1)
        await reporter.complete()
        let completed = await recorder.snapshots
        XCTAssertEqual(completed.count, 2)
        XCTAssertEqual(completed.last?.phase, .completed)
        XCTAssertEqual(completed.last?.completedBytes, 1_000)
        XCTAssertEqual(completed.last?.completedUnitCount, 1_000)
    }

    func testPhaseChangesAndCancellationBypassThrottling() async {
        let recorder = ProgressRecorder()
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .copy, title: "Copying"),
            minimumUpdateInterval: .seconds(60),
            onUpdate: { await recorder.append($0) }
        )
        await reporter.update(phase: .running, currentItemName: "first.txt")
        await reporter.update(phase: .resolvingConflict)
        await reporter.update(phase: .running, currentItemName: "second.txt")
        await reporter.cancel()
        let snapshots = await recorder.snapshots
        XCTAssertEqual(snapshots.map(\.phase), [.running, .resolvingConflict, .running, .cancelled])
        XCTAssertEqual(snapshots[2].currentItemName, "second.txt")
        XCTAssertFalse(snapshots.last?.isCancellable ?? true)
    }

    func testReporterPublishesSnapshotsInOrder() async {
        let recorder = ProgressRecorder()
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .copy, title: "Copying"),
            onUpdate: { snapshot in
                await recorder.append(snapshot)
            }
        )

        await reporter.update(phase: .running, currentItemName: "a.txt", completedUnitCount: 1, totalUnitCount: 2)
        await reporter.complete()

        let snapshots = await recorder.snapshots
        XCTAssertEqual(snapshots.map(\.phase), [.running, .completed])
        XCTAssertEqual(snapshots.first?.currentItemName, "a.txt")
    }

    func testCheckCancellationThrowsAfterCancel() async {
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .move, title: "Moving"),
            onUpdate: { _ in }
        )

        await reporter.cancel()

        do {
            try await reporter.checkCancellation()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUpdateAfterCancelDoesNotOverwriteCancelledSnapshot() async {
        let recorder = ProgressRecorder()
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .copy, title: "Copying"),
            onUpdate: { snapshot in await recorder.append(snapshot) }
        )

        await reporter.cancel()
        await reporter.update(phase: .running, currentItemName: "late.txt", completedUnitCount: 1, totalUnitCount: 2)

        let snapshot = await reporter.currentSnapshot
        XCTAssertEqual(snapshot.phase, .cancelled)
        XCTAssertFalse(snapshot.isCancellable)
    }
}

private actor ProgressRecorder {
    private(set) var snapshots: [FileOperationProgressSnapshot] = []

    func append(_ snapshot: FileOperationProgressSnapshot) {
        snapshots.append(snapshot)
    }
}
