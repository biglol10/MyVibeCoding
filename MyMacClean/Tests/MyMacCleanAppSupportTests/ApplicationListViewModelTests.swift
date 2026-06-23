import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class ApplicationListViewModelTests: XCTestCase {
    func testSelectingDifferentAppClearsStaleScanResults() {
        let first = InstalledApp(
            displayName: "First",
            bundleIdentifier: "com.example.first",
            version: nil,
            executableName: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/First.app"),
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let second = InstalledApp(
            displayName: "Second",
            bundleIdentifier: "com.example.second",
            version: nil,
            executableName: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Second.app"),
            iconIdentifier: nil,
            bundleSize: 2,
            lastOpenedAt: nil
        )
        let staleCandidate = RelatedFileCandidate(
            url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.example.first"),
            kind: .cache,
            size: 10,
            matchReason: "bundle identifier match",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel()

        viewModel.apps = [first, second]
        viewModel.selectApp(first)
        viewModel.candidates = [staleCandidate]
        viewModel.selectedCandidateIDs = [staleCandidate.id]
        viewModel.selectApp(second)

        XCTAssertEqual(viewModel.selectedApp, second)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
    }

    func testSuccessfulDeletionRemovesDeletedAppAndClearsReviewState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanAppSupportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Cursor.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.todesktop.230313mzl4w4u92", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        let deletedApp = InstalledApp(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            displayName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let remainingApp = InstalledApp(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            displayName: "Remaining",
            bundleIdentifier: "com.example.remaining",
            version: nil,
            executableName: nil,
            bundleURL: root.appendingPathComponent("Remaining.app", isDirectory: true),
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let appCandidate = RelatedFileCandidate(
            url: appURL,
            kind: .appBundle,
            size: 1,
            matchReason: "app bundle",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let cacheCandidate = RelatedFileCandidate(
            url: cacheURL,
            kind: .cache,
            size: 1,
            matchReason: "bundle identifier match",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel()

        viewModel.apps = [deletedApp, remainingApp]
        viewModel.selectApp(deletedApp)
        viewModel.candidates = [appCandidate, cacheCandidate]
        viewModel.selectedCandidateIDs = [appCandidate.id, cacheCandidate.id]

        await viewModel.deleteConfirmedItems(confirmation: "DELETE")

        XCTAssertFalse(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertEqual(viewModel.apps, [remainingApp])
        XCTAssertNil(viewModel.selectedApp)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
        XCTAssertTrue(viewModel.deletionResults.isEmpty)
        XCTAssertNil(viewModel.deletionReport)
    }

    func testSuccessfulAppDeletionRecordsReceiptWithoutLeavingInspectorReport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanReportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Report.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        let receiptURL = root.appendingPathComponent("receipts.jsonl")
        let app = InstalledApp(
            displayName: "Report",
            bundleIdentifier: "com.example.report",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let candidate = RelatedFileCandidate(
            url: appURL,
            kind: .appBundle,
            size: 1,
            matchReason: "app bundle",
            confidence: .high,
            safety: .safe,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel(receiptStore: DeletionReceiptStore(fileURL: receiptURL))

        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [candidate]
        viewModel.selectedCandidateIDs = [candidate.id]

        await viewModel.deleteConfirmedItems(confirmation: "DELETE")

        XCTAssertNil(viewModel.selectedApp)
        XCTAssertNil(viewModel.deletionReport)
        XCTAssertEqual(try DeletionReceiptStore(fileURL: receiptURL).readReceipts().count, 1)
    }

    func testSuccessfulRelatedFileDeletionKeepsSelectedAppAndReport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanRelatedFileReportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Report.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.example.report", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let receiptURL = root.appendingPathComponent("receipts.jsonl")
        let app = InstalledApp(
            displayName: "Report",
            bundleIdentifier: "com.example.report",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let candidate = RelatedFileCandidate(
            url: cacheURL,
            kind: .cache,
            size: 1,
            matchReason: "bundle identifier match",
            confidence: .high,
            safety: .safe,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel(receiptStore: DeletionReceiptStore(fileURL: receiptURL))

        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [candidate]
        viewModel.selectedCandidateIDs = [candidate.id]

        await viewModel.deleteConfirmedItems(confirmation: "DELETE")

        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertEqual(viewModel.selectedApp, app)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertEqual(viewModel.deletionReport?.statusTitle, "Deleted and verified")
        XCTAssertEqual(try DeletionReceiptStore(fileURL: receiptURL).readReceipts().count, 1)
    }
}
