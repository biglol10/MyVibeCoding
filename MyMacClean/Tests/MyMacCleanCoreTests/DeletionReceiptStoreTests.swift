import XCTest
@testable import MyMacCleanCore

final class DeletionReceiptStoreTests: XCTestCase {
    func testAppendsAndReadsDeletionReceiptWithVerificationResults() throws {
        let root = try TestFixtures.temporaryDirectory(named: "receipt-store")
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        let receipt = DeletionReceipt(
            appName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            bundlePath: "/Applications/Cursor.app",
            action: .uninstall,
            completedAt: Date(timeIntervalSince1970: 100),
            selectedCandidates: [
                DeletionReceiptCandidate(path: "/Applications/Cursor.app", kind: .appBundle, size: 10, safety: .safe, evidence: [])
            ],
            executionResults: [
                DeletionItemResult(path: "/Applications/Cursor.app", success: true, errorMessage: nil)
            ],
            verificationResults: [
                DeletionVerificationResult(path: "/Applications/Cursor.app", status: .deleted, errorMessage: nil)
            ],
            confirmationMatched: true
        )

        try store.append(receipt)

        XCTAssertEqual(try store.readReceipts(), [receipt])
    }

    func testClearReceiptsRemovesHistoryFile() throws {
        let root = try TestFixtures.temporaryDirectory(named: "receipt-store-clear")
        let receiptURL = root.appendingPathComponent("receipts.jsonl")
        let store = DeletionReceiptStore(fileURL: receiptURL)
        let receipt = DeletionReceipt(
            appName: "App",
            bundleIdentifier: nil,
            bundlePath: "/Applications/App.app",
            action: .uninstall,
            completedAt: Date(timeIntervalSince1970: 0),
            selectedCandidates: [],
            executionResults: [],
            verificationResults: [],
            confirmationMatched: true
        )

        try store.append(receipt)
        try store.clear()

        XCTAssertFalse(FileManager.default.fileExists(atPath: receiptURL.path))
        XCTAssertEqual(try store.readReceipts(), [])
    }
}
