import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class OrphanFilesViewModelTests: XCTestCase {
    func testLoadGroupsFindsOrphansFromInstalledAppsSnapshot() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanVM-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let orphan = home.appendingPathComponent("Library/Caches/com.example.deleted", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        let viewModel = OrphanFilesViewModel(homeDirectory: home, installedApps: [])

        await viewModel.loadGroups()

        XCTAssertEqual(viewModel.groups.map(\.inferredIdentifier), ["com.example.deleted"])
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
    }

    func testLoadGroupsExcludesCurrentApplicationBundleIdentifier() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanOwn-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let ownCache = home.appendingPathComponent("Library/Caches/com.local.mymacclean", isDirectory: true)
        try FileManager.default.createDirectory(at: ownCache, withIntermediateDirectories: true)
        let viewModel = OrphanFilesViewModel(
            homeDirectory: home,
            installedApps: [],
            excludedBundleIdentifiers: ["com.local.mymacclean"]
        )

        await viewModel.loadGroups()

        XCTAssertTrue(viewModel.groups.isEmpty)
    }

    func testDeleteSelectedLeftoversRemovesVerifiedFilesAndRecordsReceipt() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanDelete-\(UUID().uuidString)", isDirectory: true)
        let receiptRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanReceipt-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: receiptRoot)
        }
        let orphan = home.appendingPathComponent("Library/Caches/com.example.deleted", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        let store = DeletionReceiptStore(fileURL: receiptRoot.appendingPathComponent("receipts.jsonl"))
        let viewModel = OrphanFilesViewModel(homeDirectory: home, installedApps: [], receiptStore: store)

        await viewModel.loadGroups()
        viewModel.selectedCandidateIDs = Set(viewModel.groups.flatMap(\.candidates).map(\.id))
        await viewModel.deleteSelectedLeftovers(confirmation: "DELETE")

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(viewModel.groups.isEmpty)
        XCTAssertEqual(viewModel.deletionReport?.statusTitle, "Deleted and verified")
        let receipts = try store.readReceipts()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].action, .orphanCleanup)
        XCTAssertEqual(receipts[0].verificationResults.map(\.status), [.deleted])
    }
}
