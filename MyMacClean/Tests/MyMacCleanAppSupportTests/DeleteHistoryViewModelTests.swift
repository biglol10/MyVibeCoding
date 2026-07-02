import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class DeleteHistoryViewModelTests: XCTestCase {
    func testLoadSelectsNewestReceiptForDetails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanHistorySelection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        try store.append(receipt(appName: "Old", completedAt: Date(timeIntervalSince1970: 1)))
        try store.append(receipt(appName: "New", completedAt: Date(timeIntervalSince1970: 2)))
        let viewModel = DeleteHistoryViewModel(receiptStore: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.selectedReceipt?.appName, "New")
    }

    func testSelectingReceiptUpdatesSelectedReceiptForDetails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanHistorySelectRow-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        let first = receipt(appName: "First", completedAt: Date(timeIntervalSince1970: 1))
        let second = receipt(appName: "Second", completedAt: Date(timeIntervalSince1970: 2))
        try store.append(first)
        try store.append(second)
        let viewModel = DeleteHistoryViewModel(receiptStore: store)

        await viewModel.load()
        viewModel.selectReceipt(id: first.id)

        XCTAssertEqual(viewModel.selectedReceipt?.appName, "First")
    }

    func testSearchMovesSelectionToFirstVisibleReceipt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanHistoryFilterSelection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        try store.append(receipt(appName: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92", completedAt: Date(timeIntervalSince1970: 1)))
        try store.append(receipt(appName: "Figma", bundleIdentifier: "com.figma.Desktop", completedAt: Date(timeIntervalSince1970: 2)))
        let viewModel = DeleteHistoryViewModel(receiptStore: store)

        await viewModel.load()
        viewModel.searchText = "cursor"

        XCTAssertEqual(viewModel.filteredReceipts.map(\.appName), ["Cursor"])
        XCTAssertEqual(viewModel.selectedReceipt?.appName, "Cursor")
    }

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

    func testLoadKeepsValidReceiptsWhenHistoryContainsMalformedLines() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanHistoryMalformed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let receiptURL = root.appendingPathComponent("receipts.jsonl")
        let store = DeletionReceiptStore(fileURL: receiptURL)
        try store.append(receipt(appName: "Old", completedAt: Date(timeIntervalSince1970: 1)))
        let handle = try FileHandle(forWritingTo: receiptURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{broken history line}\n".utf8))
        try handle.close()
        try store.append(receipt(appName: "New", completedAt: Date(timeIntervalSince1970: 2)))
        let viewModel = DeleteHistoryViewModel(receiptStore: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.receipts.map(\.appName), ["New", "Old"])
        XCTAssertEqual(viewModel.selectedReceipt?.appName, "New")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSuccessfulLoadClearsPreviousErrorMessage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanHistoryClearsError-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        try store.append(receipt(appName: "Cursor", completedAt: Date(timeIntervalSince1970: 1)))
        let viewModel = DeleteHistoryViewModel(receiptStore: store)
        viewModel.errorMessage = "Previous load failed"

        await viewModel.load()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.receipts.map(\.appName), ["Cursor"])
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

    func testRequestClearHistoryRequiresExplicitConfirmation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanHistoryClearRequest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        try store.append(receipt(appName: "Cursor", completedAt: Date(timeIntervalSince1970: 1)))
        let viewModel = DeleteHistoryViewModel(receiptStore: store)
        await viewModel.load()

        viewModel.requestClearHistory()

        XCTAssertTrue(viewModel.isClearHistoryConfirmationPresented)
        XCTAssertEqual(viewModel.receipts.map(\.appName), ["Cursor"])
        XCTAssertEqual(try store.readReceipts().map(\.appName), ["Cursor"])

        viewModel.cancelClearHistory()

        XCTAssertFalse(viewModel.isClearHistoryConfirmationPresented)
        XCTAssertEqual(viewModel.receipts.map(\.appName), ["Cursor"])
    }

    func testConfirmClearHistoryRemovesReceiptsAfterRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanHistoryClearConfirm-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        try store.append(receipt(appName: "Cursor", completedAt: Date(timeIntervalSince1970: 1)))
        let viewModel = DeleteHistoryViewModel(receiptStore: store)
        await viewModel.load()

        viewModel.requestClearHistory()
        viewModel.confirmClearHistory()

        XCTAssertFalse(viewModel.isClearHistoryConfirmationPresented)
        XCTAssertTrue(viewModel.receipts.isEmpty)
        XCTAssertNil(viewModel.selectedReceiptID)
        XCTAssertEqual(try store.readReceipts(), [])
    }

    private func receipt(
        appName: String,
        bundleIdentifier: String? = nil,
        completedAt: Date
    ) -> DeletionReceipt {
        DeletionReceipt(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            bundlePath: "/Applications/\(appName).app",
            action: .uninstall,
            completedAt: completedAt,
            selectedCandidates: [],
            executionResults: [],
            verificationResults: [],
            confirmationMatched: true
        )
    }
}
