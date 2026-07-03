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

    func testReadReceiptsSkipsMalformedLinesAndKeepsValidHistory() throws {
        let root = try TestFixtures.temporaryDirectory(named: "receipt-store-malformed")
        let receiptURL = root.appendingPathComponent("receipts.jsonl")
        let store = DeletionReceiptStore(fileURL: receiptURL)
        let first = Self.receipt(appName: "First", completedAt: Date(timeIntervalSince1970: 1))
        let second = Self.receipt(appName: "Second", completedAt: Date(timeIntervalSince1970: 2))

        try store.append(first)
        let invalidLine = Data("{this is not valid json}\n".utf8)
        let handle = try FileHandle(forWritingTo: receiptURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: invalidLine)
        try handle.close()
        try store.append(second)

        XCTAssertEqual(try store.readReceipts(), [first, second])
    }

    func testDefaultFileURLUsesApplicationSupportReceiptPath() throws {
        let home = try TestFixtures.temporaryDirectory(named: "receipt-store-default-path")

        XCTAssertEqual(
            DeletionReceiptStore.defaultFileURL(homeDirectory: home),
            home.appendingPathComponent("Library/Application Support/MyMacClean/deletion-receipts.jsonl")
        )
    }

    func testConcurrentAppendsKeepEveryReceipt() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "receipt-store-concurrent")
        let receiptURL = root.appendingPathComponent("receipts.jsonl")

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    let store = DeletionReceiptStore(fileURL: receiptURL)
                    try store.append(Self.receipt(appName: "App \(index)", completedAt: Date(timeIntervalSince1970: TimeInterval(index))))
                }
            }

            try await group.waitForAll()
        }

        XCTAssertEqual(try DeletionReceiptStore(fileURL: receiptURL).readReceipts().count, 40)
    }

    func testSupportsLargeFileCleanupReceipts() throws {
        let root = try TestFixtures.temporaryDirectory(named: "receipt-large-files")
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        let receipt = DeletionReceipt(
            appName: "Large Files",
            bundleIdentifier: nil,
            bundlePath: root.path,
            action: .largeFileCleanup,
            completedAt: Date(timeIntervalSince1970: 10),
            selectedCandidates: [],
            executionResults: [],
            verificationResults: [],
            confirmationMatched: true
        )

        try store.append(receipt)

        XCTAssertEqual(try store.readReceipts(), [receipt])
    }

    func testSupportsDeveloperCacheCleanupReceipts() throws {
        let root = try TestFixtures.temporaryDirectory(named: "receipt-developer-cache")
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        let receipt = DeletionReceipt(
            appName: "Developer Cache",
            bundleIdentifier: nil,
            bundlePath: root.path,
            action: .developerCacheCleanup,
            completedAt: Date(timeIntervalSince1970: 11),
            selectedCandidates: [],
            executionResults: [],
            verificationResults: [],
            confirmationMatched: true
        )

        try store.append(receipt)

        XCTAssertEqual(try store.readReceipts(), [receipt])
    }

    private static func receipt(appName: String, completedAt: Date) -> DeletionReceipt {
        DeletionReceipt(
            appName: appName,
            bundleIdentifier: nil,
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
