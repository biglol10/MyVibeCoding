import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class LargeFilesViewModelTests: XCTestCase {
    func testDefaultScanRootsUseConservativeDownloadsRoot() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

        let roots = LargeFilesViewModel.defaultScanRoots(homeDirectory: home)

        XCTAssertEqual(
            roots,
            [
                home.appendingPathComponent("Downloads", isDirectory: true)
            ]
        )
    }

    func testScanLoadsLargeFilesWithoutDefaultSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanLargeFilesVM-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("movie.mov")
        try Data(repeating: 1, count: 1_500).write(to: file)

        let viewModel = LargeFilesViewModel(scanRoots: [root], minimumSize: 1_000)

        await viewModel.scan()

        XCTAssertEqual(viewModel.candidates.map(\.url), [file])
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
        XCTAssertEqual(viewModel.totalBytes, 1_500)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFilterAndSortVisibleCandidates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanLargeFilesFilter-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("archive.zip")
        let video = root.appendingPathComponent("video.mov")
        try Data(repeating: 1, count: 2_000).write(to: archive)
        try Data(repeating: 1, count: 3_000).write(to: video)

        let viewModel = LargeFilesViewModel(scanRoots: [root], minimumSize: 1_000)
        await viewModel.scan()
        viewModel.searchText = "archive"

        XCTAssertEqual(viewModel.visibleCandidates.map(\.url), [archive])
    }

    func testDeleteSelectedFilesRecordsReceiptAndRemovesVerifiedItems() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanLargeFilesDelete-\(UUID().uuidString)", isDirectory: true)
        let receiptRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanLargeFilesReceipt-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: receiptRoot)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("movie.mov")
        try Data(repeating: 1, count: 1_500).write(to: file)
        let store = DeletionReceiptStore(fileURL: receiptRoot.appendingPathComponent("receipts.jsonl"))
        let remover = DeletionFileRemover(
            trash: { url in try FileManager.default.removeItem(at: url) },
            remove: { url in try FileManager.default.removeItem(at: url) }
        )

        let viewModel = LargeFilesViewModel(
            scanRoots: [root],
            minimumSize: 1_000,
            executor: DeletionExecutor(
                fileRemover: remover,
                deletionProtectionPolicy: UserFileCleanupPolicy(allowedRoots: [root]).deletionProtectionPolicy
            ),
            receiptStore: store
        )

        await viewModel.scan()
        viewModel.selectedCandidateIDs = Set(viewModel.candidates.map(\.id))
        await viewModel.moveSelectedToTrash(confirmation: "DELETE")

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(viewModel.candidates.isEmpty)
        let receipts = try store.readReceipts()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].action, .largeFileCleanup)
        XCTAssertEqual(receipts[0].verificationResults.map(\.status), [.deleted])
    }
}
