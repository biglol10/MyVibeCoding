import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

final class DeletionReportViewModelTests: XCTestCase {
    func testSummarizesVerifiedDeletion() {
        let report = DeletionReportViewModel(
            receipt: DeletionReceipt(
                appName: "Cursor",
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                bundlePath: "/Applications/Cursor.app",
                action: .uninstall,
                selectedCandidates: [],
                executionResults: [],
                verificationResults: [
                    DeletionVerificationResult(path: "/Applications/Cursor.app", status: .deleted, errorMessage: nil),
                    DeletionVerificationResult(path: "/Users/me/Library/Caches/com.todesktop.230313mzl4w4u92", status: .deleted, errorMessage: nil)
                ],
                confirmationMatched: true
            )
        )

        XCTAssertEqual(report.statusTitle, "Deleted and verified")
        XCTAssertEqual(report.deletedCount, 2)
        XCTAssertEqual(report.remainingCount, 0)
        XCTAssertTrue(report.remainingPaths.isEmpty)
    }

    func testSummarizesPartialDeletion() {
        let report = DeletionReportViewModel(
            receipt: DeletionReceipt(
                appName: "Cursor",
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                bundlePath: "/Applications/Cursor.app",
                action: .uninstall,
                selectedCandidates: [],
                executionResults: [],
                verificationResults: [
                    DeletionVerificationResult(path: "/Applications/Cursor.app", status: .deleted, errorMessage: nil),
                    DeletionVerificationResult(path: "/Users/me/Library/Caches/com.todesktop.230313mzl4w4u92", status: .stillExists, errorMessage: nil)
                ],
                confirmationMatched: true
            )
        )

        XCTAssertEqual(report.statusTitle, "Deleted with remaining items")
        XCTAssertEqual(report.deletedCount, 1)
        XCTAssertEqual(report.remainingCount, 1)
        XCTAssertEqual(report.remainingPaths, ["/Users/me/Library/Caches/com.todesktop.230313mzl4w4u92"])
    }

    func testSummarizesExecutionFailureBeforeRemainingItems() {
        let report = DeletionReportViewModel(
            receipt: DeletionReceipt(
                appName: "Cursor",
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                bundlePath: "/Applications/Cursor.app",
                action: .uninstall,
                selectedCandidates: [],
                executionResults: [
                    DeletionItemResult(path: "/Applications/Cursor.app", success: false, errorMessage: "Operation not permitted")
                ],
                verificationResults: [
                    DeletionVerificationResult(path: "/Applications/Cursor.app", status: .stillExists, errorMessage: nil)
                ],
                confirmationMatched: true
            )
        )

        XCTAssertEqual(report.statusTitle, "Deletion failed")
        XCTAssertEqual(report.deletedCount, 0)
        XCTAssertEqual(report.remainingCount, 1)
        XCTAssertEqual(report.remainingPaths, ["/Applications/Cursor.app"])
    }
}
