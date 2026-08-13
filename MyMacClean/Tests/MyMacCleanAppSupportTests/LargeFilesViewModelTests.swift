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

    func testChangingScanRootClearsStaleResultsSelectionAndCoverage() async throws {
        let firstRoot = try temporaryDirectory(named: "root-change-first")
        let secondRoot = try temporaryDirectory(named: "root-change-second")
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        try Data(repeating: 1, count: 10).write(to: firstRoot.appendingPathComponent("large.bin"))
        let viewModel = LargeFilesViewModel(scanRoots: [firstRoot], minimumSize: 1)
        await viewModel.scan()
        viewModel.selectedCandidateIDs = Set(viewModel.candidates.map(\.id))
        viewModel.scanIssues = [ScanIssue(path: firstRoot.path, message: "stale", permissionRelated: false)]

        XCTAssertTrue(viewModel.setScanRoot(secondRoot))
        XCTAssertEqual(viewModel.activeScanRoot, secondRoot.standardizedFileURL)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
        XCTAssertTrue(viewModel.scanIssues.isEmpty)
        XCTAssertNil(viewModel.deletionReport)
        XCTAssertFalse(viewModel.hasScanned)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRejectsBroadOrNonDirectoryRootWithoutReplacingCurrentRoot() throws {
        let downloads = try temporaryDirectory(named: "root-validation")
        defer { try? FileManager.default.removeItem(at: downloads) }
        let file = downloads.appendingPathComponent("not-a-folder")
        try Data("file".utf8).write(to: file)
        let viewModel = LargeFilesViewModel(scanRoots: [downloads], minimumSize: 1)

        XCTAssertFalse(viewModel.setScanRoot(URL(fileURLWithPath: "/", isDirectory: true)))
        XCTAssertEqual(viewModel.activeScanRoot, downloads.standardizedFileURL)
        XCTAssertNotNil(viewModel.errorMessage)

        XCTAssertFalse(viewModel.setScanRoot(file))
        XCTAssertEqual(viewModel.activeScanRoot, downloads.standardizedFileURL)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testNestedFilesAppearOnlyWhenIncludeSubfoldersIsEnabled() async throws {
        let root = try temporaryDirectory(named: "recursive-toggle")
        defer { try? FileManager.default.removeItem(at: root) }
        let direct = root.appendingPathComponent("direct.bin")
        let nestedFolder = root.appendingPathComponent("Nested", isDirectory: true)
        let nested = nestedFolder.appendingPathComponent("nested.bin")
        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: direct)
        try Data(repeating: 1, count: 20).write(to: nested)
        let viewModel = LargeFilesViewModel(scanRoots: [root], minimumSize: 1)

        XCTAssertFalse(viewModel.includeSubfolders)
        await viewModel.scan()
        XCTAssertEqual(viewModel.candidates.map(\.url), [direct])

        viewModel.includeSubfolders = true
        XCTAssertFalse(viewModel.hasScanned)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        await viewModel.scan()

        XCTAssertEqual(Set(viewModel.candidates.map(\.url)), [direct, nested])
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanLargeFilesTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.standardizedFileURL
    }
}
