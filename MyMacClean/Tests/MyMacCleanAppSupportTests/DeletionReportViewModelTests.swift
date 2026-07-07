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

    func testSummarizesExecutionFailureWithVerifiedDeletedItemsAsPartialDeletion() {
        let report = DeletionReportViewModel(
            receipt: DeletionReceipt(
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
        )

        XCTAssertEqual(report.statusTitle, "Deleted with remaining items")
        XCTAssertEqual(report.deletedCount, 1)
        XCTAssertEqual(report.remainingCount, 1)
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

    func testBuildsCopyableReportTextWithRemainingPathsAndErrors() {
        let report = DeletionReportViewModel(
            receipt: DeletionReceipt(
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
        )

        XCTAssertEqual(report.copyableReportText, """
        MyMacClean Deletion Report
        App: Cursor
        Bundle ID: com.todesktop.230313mzl4w4u92
        Action: uninstall
        Status: Deleted with remaining items
        Deleted: 1
        Remaining: 1

        Remaining Paths:
        /Users/me/Library/Caches/com.todesktop.230313mzl4w4u92

        Errors:
        /Users/me/Library/Caches/com.todesktop.230313mzl4w4u92 - Operation not permitted
        """)
    }

    func testExposesStructuredErrorLogsForHistoryDetails() {
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
                    DeletionVerificationResult(path: "/Applications/Cursor.app", status: .permissionDenied, errorMessage: "Full Disk Access is required")
                ],
                confirmationMatched: true
            )
        )

        XCTAssertEqual(report.errorLogs, [
            DeletionErrorLog(path: "/Applications/Cursor.app", message: "Operation not permitted"),
            DeletionErrorLog(path: "/Applications/Cursor.app", message: "Full Disk Access is required")
        ])
        XCTAssertEqual(report.errorLogLines, [
            "/Applications/Cursor.app - Operation not permitted",
            "/Applications/Cursor.app - Full Disk Access is required"
        ])
    }

    func testBuildsSuccessToastPresentationFromVerifiedDeletion() {
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

        let toast = DeletionToastPresentation(report: report)

        XCTAssertEqual(toast.severity, .success)
        XCTAssertEqual(toast.title, "Deletion succeeded")
        XCTAssertEqual(toast.message, "2 deleted, 0 remaining")
        XCTAssertTrue(toast.detailLines.isEmpty)
    }

    func testBuildsErrorToastPresentationFromFailedDeletion() {
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

        let toast = DeletionToastPresentation(report: report)

        XCTAssertEqual(toast.severity, .error)
        XCTAssertEqual(toast.title, "Deletion failed")
        XCTAssertEqual(toast.message, "0 deleted, 1 remaining")
        XCTAssertEqual(toast.detailLines, ["/Applications/Cursor.app - Operation not permitted"])
    }

    func testSummarizesStartupItemChangeWithoutDeletionLanguage() {
        let report = DeletionReportViewModel(
            receipt: DeletionReceipt(
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
        )

        XCTAssertEqual(report.statusTitle, "Startup item changed")
        XCTAssertEqual(report.completedCountTitle, "Changed")
        XCTAssertEqual(report.completedCount, 1)
        XCTAssertEqual(report.summaryLine, "1 changed, 0 remaining")
        XCTAssertTrue(report.copyableReportText.contains("MyMacClean Startup Item Report"))
        XCTAssertTrue(report.copyableReportText.contains("Changed: 1"))
        XCTAssertFalse(report.copyableReportText.contains("Deleted:"))
    }
}
