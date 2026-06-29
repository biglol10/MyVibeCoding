import XCTest
@testable import MyMacFinder

final class FileOperationProgressReporterTests: XCTestCase {
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
