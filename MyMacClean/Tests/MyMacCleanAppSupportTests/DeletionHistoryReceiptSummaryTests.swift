import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

final class DeletionHistoryReceiptSummaryTests: XCTestCase {
    func testMarksExecutionFailureWithNoDeletedItemsAsFailedEvenWhenItemsRemain() {
        let receipt = DeletionReceipt(
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

        let summary = DeletionHistoryReceiptSummary(receipt: receipt)

        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.statusTitle, "Failed")
        XCTAssertEqual(summary.deletedCount, 0)
        XCTAssertEqual(summary.remainingCount, 1)
        XCTAssertEqual(summary.remainingPaths, ["/Applications/Cursor.app"])
    }

    func testMarksPartialDeletionAsNeedsReview() {
        let receipt = DeletionReceipt(
            appName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            bundlePath: "/Applications/Cursor.app",
            action: .uninstall,
            selectedCandidates: [],
            executionResults: [
                DeletionItemResult(path: "/Users/me/Library/Caches/com.todesktop.230313mzl4w4u92", success: false, errorMessage: "Operation not permitted")
            ],
            verificationResults: [
                DeletionVerificationResult(path: "/Applications/Cursor.app", status: .deleted, errorMessage: nil),
                DeletionVerificationResult(path: "/Users/me/Library/Caches/com.todesktop.230313mzl4w4u92", status: .stillExists, errorMessage: nil)
            ],
            confirmationMatched: true
        )

        let summary = DeletionHistoryReceiptSummary(receipt: receipt)

        XCTAssertEqual(summary.status, .needsReview)
        XCTAssertEqual(summary.statusTitle, "Needs Review")
        XCTAssertEqual(summary.deletedCount, 1)
        XCTAssertEqual(summary.remainingCount, 1)
    }

    func testMarksVerifiedDeletionAsVerified() {
        let receipt = DeletionReceipt(
            appName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            bundlePath: "/Applications/Cursor.app",
            action: .uninstall,
            selectedCandidates: [],
            executionResults: [
                DeletionItemResult(path: "/Applications/Cursor.app", success: true, errorMessage: nil)
            ],
            verificationResults: [
                DeletionVerificationResult(path: "/Applications/Cursor.app", status: .deleted, errorMessage: nil)
            ],
            confirmationMatched: true
        )

        let summary = DeletionHistoryReceiptSummary(receipt: receipt)

        XCTAssertEqual(summary.status, .verified)
        XCTAssertEqual(summary.statusTitle, "Verified")
        XCTAssertEqual(summary.deletedCount, 1)
        XCTAssertEqual(summary.remainingCount, 0)
        XCTAssertTrue(summary.remainingPaths.isEmpty)
    }

    func testMarksStartupItemChangeAsChanged() {
        let receipt = DeletionReceipt(
            appName: "com.example.agent",
            bundleIdentifier: nil,
            bundlePath: "/Users/me/Library/LaunchAgents/com.example.agent.plist",
            action: .startupItemDisable,
            selectedCandidates: [],
            executionResults: [
                DeletionItemResult(path: "/Users/me/Library/LaunchAgents/com.example.agent.plist", success: true, errorMessage: nil)
            ],
            verificationResults: [
                DeletionVerificationResult(path: "/Users/me/Library/LaunchAgents/com.example.agent.plist", status: .deleted, errorMessage: nil)
            ],
            confirmationMatched: true
        )

        let summary = DeletionHistoryReceiptSummary(receipt: receipt)

        XCTAssertEqual(summary.status, .verified)
        XCTAssertEqual(summary.statusTitle, "Changed")
        XCTAssertEqual(summary.primaryCountTitle, "Changed")
        XCTAssertEqual(summary.primaryCount, 1)
        XCTAssertEqual(summary.remainingCount, 0)
    }
}
