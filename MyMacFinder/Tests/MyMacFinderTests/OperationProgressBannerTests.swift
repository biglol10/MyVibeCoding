import XCTest
@testable import MyMacFinder

final class OperationProgressBannerTests: XCTestCase {
    func testCompletedSnapshotIsDismissible() {
        let snapshot = FileOperationProgressSnapshot(
            kind: .copy,
            phase: .completed,
            title: "Copied 2 items",
            completedUnitCount: 2,
            totalUnitCount: 2,
            isCancellable: false
        )

        XCTAssertTrue(snapshot.isTerminal)
    }
}
