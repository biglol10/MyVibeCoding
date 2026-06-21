import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class DeleteHistoryViewModelTests: XCTestCase {
    func testLoadsReceiptsNewestFirst() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanHistory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        try store.append(DeletionReceipt(appName: "Old", bundleIdentifier: nil, bundlePath: "/Applications/Old.app", action: .uninstall, completedAt: Date(timeIntervalSince1970: 1), selectedCandidates: [], executionResults: [], verificationResults: [], confirmationMatched: true))
        try store.append(DeletionReceipt(appName: "New", bundleIdentifier: nil, bundlePath: "/Applications/New.app", action: .uninstall, completedAt: Date(timeIntervalSince1970: 2), selectedCandidates: [], executionResults: [], verificationResults: [], confirmationMatched: true))
        let viewModel = DeleteHistoryViewModel(receiptStore: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.receipts.map(\.appName), ["New", "Old"])
    }

    func testSearchFiltersByAppNameAndPath() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanHistorySearch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        try store.append(DeletionReceipt(appName: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92", bundlePath: "/Applications/Cursor.app", action: .uninstall, selectedCandidates: [], executionResults: [], verificationResults: [], confirmationMatched: true))
        try store.append(DeletionReceipt(appName: "Figma", bundleIdentifier: "com.figma.Desktop", bundlePath: "/Applications/Figma.app", action: .uninstall, selectedCandidates: [], executionResults: [], verificationResults: [], confirmationMatched: true))
        let viewModel = DeleteHistoryViewModel(receiptStore: store)

        await viewModel.load()
        viewModel.searchText = "cursor"

        XCTAssertEqual(viewModel.filteredReceipts.map(\.appName), ["Cursor"])
    }
}
