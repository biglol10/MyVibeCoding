import XCTest
@testable import MyMacFinder

final class FileOperationProgressTests: XCTestCase {
    func testFractionCompletedUsesUnitsWhenByteTotalsAreMissing() {
        let snapshot = FileOperationProgressSnapshot(
            id: FileOperationID(),
            kind: .copy,
            phase: .running,
            title: "Copying 4 items",
            currentItemName: "b.txt",
            completedUnitCount: 1,
            totalUnitCount: 4,
            completedBytes: nil,
            totalBytes: nil,
            isCancellable: true
        )

        XCTAssertEqual(snapshot.fractionCompleted, 0.25)
        XCTAssertEqual(snapshot.statusText, "1 of 4")
    }

    func testFractionCompletedPrefersBytesWhenAvailable() {
        let snapshot = FileOperationProgressSnapshot(
            id: FileOperationID(),
            kind: .copy,
            phase: .running,
            title: "Copying 1 item",
            currentItemName: "large.mov",
            completedUnitCount: 0,
            totalUnitCount: 1,
            completedBytes: 512,
            totalBytes: 1024,
            isCancellable: true
        )

        XCTAssertEqual(snapshot.fractionCompleted, 0.5)
        XCTAssertEqual(snapshot.statusText, "512 bytes of 1 KB")
    }

    func testAutoDismissibleCompletionRequiresMatchingCompletedSnapshot() {
        let id = FileOperationID()
        let otherID = FileOperationID()

        XCTAssertTrue(
            FileOperationProgressSnapshot(
                id: id,
                kind: .copy,
                phase: .completed,
                title: "Copying"
            )
            .isAutoDismissibleCompletion(for: id)
        )
        XCTAssertFalse(
            FileOperationProgressSnapshot(
                id: id,
                kind: .copy,
                phase: .failed,
                title: "Copying"
            )
            .isAutoDismissibleCompletion(for: id)
        )
        XCTAssertFalse(
            FileOperationProgressSnapshot(
                id: id,
                kind: .copy,
                phase: .running,
                title: "Copying"
            )
            .isAutoDismissibleCompletion(for: id)
        )
        XCTAssertFalse(
            FileOperationProgressSnapshot(
                id: otherID,
                kind: .copy,
                phase: .completed,
                title: "Copying"
            )
            .isAutoDismissibleCompletion(for: id)
        )
    }
}
