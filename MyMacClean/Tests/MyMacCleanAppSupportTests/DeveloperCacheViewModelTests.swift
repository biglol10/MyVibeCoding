import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class DeveloperCacheViewModelTests: XCTestCase {
    func testScanDefaultSelectsOnlySafeCandidates() async throws {
        let home = try temporaryHome(named: "developer-cache-vm-default-selection")
        defer { try? FileManager.default.removeItem(at: home) }
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        let archives = home.appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)
        let dockerStorage = home.appendingPathComponent("Library/Containers/com.docker.docker/Data", isDirectory: true)
        try writePayload(in: derivedData, name: "Build/data.bin", size: 12)
        try writePayload(in: archives, name: "App.xcarchive/info.plist", size: 13)
        try writePayload(in: dockerStorage, name: "vms/0/disk.raw", size: 14)

        let viewModel = DeveloperCacheViewModel(homeDirectory: home, dockerStorageURL: dockerStorage)

        await viewModel.scan()

        XCTAssertEqual(viewModel.candidates.map(\.tool), [.xcodeDerivedData, .xcodeArchives, .docker])
        XCTAssertEqual(viewModel.selectedCandidates.map(\.tool), [.xcodeDerivedData])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.hasScanned)
    }

    func testFilterAndSortVisibleCandidates() async throws {
        let home = try temporaryHome(named: "developer-cache-vm-filter")
        defer { try? FileManager.default.removeItem(at: home) }
        let npm = home.appendingPathComponent(".npm", isDirectory: true)
        let swiftPM = home.appendingPathComponent("Library/Caches/org.swift.swiftpm", isDirectory: true)
        try writePayload(in: npm, name: "_cacache/blob", size: 10_000)
        try writePayload(in: swiftPM, name: "repositories/blob", size: 10)
        let viewModel = DeveloperCacheViewModel(homeDirectory: home)

        await viewModel.scan()
        viewModel.searchText = "npm"

        XCTAssertEqual(viewModel.visibleCandidates.map(\.tool), [.npm])

        viewModel.searchText = ""
        viewModel.sort = .sizeDescending

        XCTAssertEqual(viewModel.visibleCandidates.first?.tool, .npm)
    }

    func testReadOnlyCandidatesAreExcludedFromSelectedCandidatesEvenIfMarkedSelected() async throws {
        let home = try temporaryHome(named: "developer-cache-vm-read-only")
        defer { try? FileManager.default.removeItem(at: home) }
        let dockerStorage = home.appendingPathComponent("Library/Containers/com.docker.docker/Data", isDirectory: true)
        try writePayload(in: dockerStorage, name: "vms/0/disk.raw", size: 14)
        let viewModel = DeveloperCacheViewModel(homeDirectory: home, dockerStorageURL: dockerStorage)

        await viewModel.scan()
        viewModel.selectedCandidateIDs = Set(viewModel.candidates.map(\.id))

        XCTAssertTrue(viewModel.selectedCandidates.isEmpty)
    }

    func testMoveSelectedCachesToTrashRecordsReceiptAndRemovesVerifiedItems() async throws {
        let home = try temporaryHome(named: "developer-cache-vm-delete")
        let receiptRoot = try temporaryHome(named: "developer-cache-vm-receipts")
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: receiptRoot)
        }
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        try writePayload(in: derivedData, name: "Build/data.bin", size: 12)
        let store = DeletionReceiptStore(fileURL: receiptRoot.appendingPathComponent("receipts.jsonl"))
        let remover = DeletionFileRemover(
            trash: { url in try FileManager.default.removeItem(at: url) },
            remove: { url in try FileManager.default.removeItem(at: url) }
        )

        let viewModel = DeveloperCacheViewModel(
            homeDirectory: home,
            executor: DeletionExecutor(
                fileRemover: remover,
                deletionProtectionPolicy: UserFileCleanupPolicy(allowedRoots: [derivedData]).deletionProtectionPolicy
            ),
            receiptStore: store
        )

        await viewModel.scan()
        await viewModel.moveSelectedToTrash(confirmation: "DELETE")

        XCTAssertFalse(FileManager.default.fileExists(atPath: derivedData.path))
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertEqual(viewModel.deletionReport?.statusTitle, "Deleted and verified")
        let receipts = try store.readReceipts()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].action, .developerCacheCleanup)
        XCTAssertEqual(receipts[0].verificationResults.map(\.status), [.deleted])
    }

    func testMoveSelectedCachesToTrashBlocksDerivedDataWhileXcodeIsRunning() async throws {
        let home = try temporaryHome(named: "developer-cache-vm-xcode-running")
        let receiptRoot = try temporaryHome(named: "developer-cache-vm-xcode-running-receipts")
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: receiptRoot)
        }
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        try writePayload(in: derivedData, name: "Build/data.bin", size: 12)
        let store = DeletionReceiptStore(fileURL: receiptRoot.appendingPathComponent("receipts.jsonl"))
        let remover = DeletionFileRemover(
            trash: { url in try FileManager.default.removeItem(at: url) },
            remove: { url in try FileManager.default.removeItem(at: url) }
        )

        let viewModel = DeveloperCacheViewModel(
            homeDirectory: home,
            executor: DeletionExecutor(
                fileRemover: remover,
                deletionProtectionPolicy: UserFileCleanupPolicy(allowedRoots: [derivedData]).deletionProtectionPolicy
            ),
            receiptStore: store,
            runningApplicationMonitor: RunningApplicationMonitor(isRunning: { app in
                app.bundleIdentifier == "com.apple.dt.Xcode"
            })
        )

        await viewModel.scan()
        await viewModel.moveSelectedToTrash(confirmation: "DELETE")

        XCTAssertTrue(FileManager.default.fileExists(atPath: derivedData.path))
        XCTAssertNil(viewModel.deletionReport)
        XCTAssertEqual(viewModel.errorMessage, "Quit Xcode before deleting DerivedData.")
        XCTAssertTrue(try store.readReceipts().isEmpty)
        XCTAssertFalse(viewModel.isDeleting)
    }

    private func temporaryHome(named name: String) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacClean-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func writePayload(in directory: URL, name: String, size: Int) throws {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: size).write(to: url)
    }
}
