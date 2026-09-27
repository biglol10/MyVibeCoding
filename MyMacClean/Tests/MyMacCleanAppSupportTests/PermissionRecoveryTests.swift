import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class PermissionRecoveryTests: XCTestCase {
    func testPermissionFailureSurvivesRestartThenLiveTrashRetrySucceeds() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacClean-PermissionRecovery-\(UUID())")
        let file = home.appendingPathComponent("Library/Caches/com.audit.retry/payload")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("disposable permission fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: home) }
        let app = InstalledApp(displayName: "Permission Fixture", bundleIdentifier: "com.audit.retry", version: nil, executableName: nil, bundleURL: home.appendingPathComponent("Fixture.app"), iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: file, kind: .cache, size: 29, matchReason: "fixture", confidence: .high, defaultSelected: false, requiresManualReview: true, isProtected: false)
        let receiptURL = home.appendingPathComponent("receipts.jsonl")
        let deniedExecutor = DeletionExecutor(fileRemover: DeletionFileRemover(trash: { _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES), userInfo: [NSLocalizedDescriptionKey: "접근 권한이 없습니다"])
        }, remove: { _ in XCTFail("Permanent deletion must not run") }), protectionPolicy: ProtectionPolicy(homeDirectory: home))
        let first = ApplicationListViewModel(executor: deniedExecutor, receiptStore: DeletionReceiptStore(fileURL: receiptURL))
        first.apps = [app]; first.selectApp(app); first.candidates = [candidate]; first.selectedCandidateIDs = [candidate.id]
        let denied = await first.deleteConfirmedItems(confirmation: "DELETE")
        let deniedReport = try XCTUnwrap(denied)
        XCTAssertTrue(deniedReport.hasFullDiskAccessFailure)
        XCTAssertFalse(deniedReport.isFullySuccessful)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        // A new store and model represent the state reconstructed after relaunch.
        let reopenedStore = DeletionReceiptStore(fileURL: receiptURL)
        let savedFailure = try XCTUnwrap(reopenedStore.readReceipts().last)
        XCTAssertTrue(DeletionReportViewModel(receipt: savedFailure).hasFullDiskAccessFailure)
        XCTAssertEqual(savedFailure.deletionMode, .moveToTrash)
        let second = ApplicationListViewModel(executor: DeletionExecutor(protectionPolicy: ProtectionPolicy(homeDirectory: home)), receiptStore: reopenedStore)
        second.apps = [app]; second.selectApp(app); second.candidates = [candidate]; second.selectedCandidateIDs = [candidate.id]
        let successful = await second.deleteConfirmedItems(confirmation: "DELETE")
        let report = try XCTUnwrap(successful)
        XCTAssertTrue(report.isFullySuccessful)
        let trashPath = try XCTUnwrap(report.receipt.executionResults.first?.trashPath)
        defer { try? FileManager.default.removeItem(atPath: trashPath) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashPath))
        XCTAssertEqual(try reopenedStore.readReceipts().count, 2)
        XCTAssertTrue(report.copyableReportText.contains(trashPath))
    }

    func testReadableProbeDoesNotHideDeniedProtectedDirectory() {
        let first = URL(fileURLWithPath: "/probe/first")
        let second = URL(fileURLWithPath: "/probe/second")
        let probe = FullDiskAccessProbe(protectedURLs: [first, second]) { url in
            if url == second { throw CocoaError(.fileReadNoPermission) }
            return []
        }
        XCTAssertEqual(probe.status(), .missing)
    }

    func testSearchCountsHiddenSelectionsAndSelectedOnlyFilters() {
        let model = LargeFilesViewModel()
        let first = LargeFileCandidate(url: URL(fileURLWithPath: "/tmp/alpha.zip"), size: 600_000_000, modifiedAt: nil, kind: .archive, rootURL: URL(fileURLWithPath: "/tmp"), defaultSelected: false)
        let second = LargeFileCandidate(url: URL(fileURLWithPath: "/tmp/beta.zip"), size: 700_000_000, modifiedAt: nil, kind: .archive, rootURL: URL(fileURLWithPath: "/tmp"), defaultSelected: false)
        model.candidates = [first, second]
        model.selectedCandidateIDs = [first.id]
        model.searchText = "beta"
        XCTAssertEqual(model.hiddenSelectionCount, 1)
        model.searchText = ""
        model.showSelectedOnly = true
        XCTAssertEqual(model.visibleCandidates, [first])
        model.minimumSize = 100 * 1_024 * 1_024
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertTrue(model.selectedCandidateIDs.isEmpty)
    }

}
