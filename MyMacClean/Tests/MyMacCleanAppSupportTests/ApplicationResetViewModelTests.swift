import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class ApplicationResetViewModelTests: XCTestCase {
    func testCleanupModeExposesResetCopyAndConfirmation() {
        XCTAssertEqual(ApplicationCleanupMode.uninstall.title, "Uninstall")
        XCTAssertEqual(ApplicationCleanupMode.resetData.title, "Reset Data")
        XCTAssertEqual(ApplicationCleanupMode.resetData.confirmationPhrase, "RESET")
        XCTAssertTrue(ApplicationCleanupMode.resetData.isTrashOnly)
    }

    func testResetExcludesAppBundleAndProtectedCandidatesRegardlessOfCurrentCleanupMode() async throws {
        let home = try temporaryDirectory(named: "reset-plan")
        defer { try? FileManager.default.removeItem(at: home) }
        let appURL = try makeAppBundle(root: home, name: "Reset Plan", bundleIdentifier: "com.example.reset-plan")
        let cacheURL = home.appendingPathComponent("Library/Caches/com.example.reset-plan", isDirectory: true)
        let protectedURL = home.appendingPathComponent("Documents/Reset Plan Export", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: protectedURL, withIntermediateDirectories: true)
        let app = installedApp(at: appURL, name: "Reset Plan", bundleIdentifier: "com.example.reset-plan")
        let appCandidate = candidate(at: appURL, kind: .appBundle)
        let cacheCandidate = candidate(at: cacheURL, kind: .cache)
        let protectedCandidate = candidate(at: protectedURL, kind: .unknown, isProtected: true)
        let receiptURL = home.appendingPathComponent("receipts.jsonl")
        let viewModel = ApplicationListViewModel(
            executor: removingExecutor(home: home),
            receiptStore: DeletionReceiptStore(fileURL: receiptURL),
            relatedFileScanning: RelatedFileScanning { _ in ScanResult(value: [], issues: []) }
        )

        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [appCandidate, cacheCandidate, protectedCandidate]
        viewModel.selectedCandidateIDs = [appCandidate.id, cacheCandidate.id, protectedCandidate.id]
        XCTAssertEqual(viewModel.cleanupMode, .uninstall)

        let report = await viewModel.resetSelectedData(confirmation: "RESET")

        XCTAssertEqual(report?.receipt.selectedCandidates.map(\.path), [cacheURL.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedURL.path))
        XCTAssertEqual(viewModel.selectedApp, app)
        XCTAssertEqual(viewModel.reviewCandidates, [])
    }

    func testResetRequiresResetPhraseAndLeavesFilesUntouchedForDelete() async throws {
        let home = try temporaryDirectory(named: "reset-confirmation")
        defer { try? FileManager.default.removeItem(at: home) }
        let appURL = try makeAppBundle(root: home, name: "Reset Confirmation", bundleIdentifier: "com.example.reset-confirmation")
        let cacheURL = home.appendingPathComponent("Library/Caches/com.example.reset-confirmation", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let app = installedApp(at: appURL, name: "Reset Confirmation", bundleIdentifier: "com.example.reset-confirmation")
        let cacheCandidate = candidate(at: cacheURL, kind: .cache)
        let viewModel = ApplicationListViewModel(
            executor: removingExecutor(home: home),
            receiptStore: DeletionReceiptStore(fileURL: home.appendingPathComponent("receipts.jsonl")),
            relatedFileScanning: RelatedFileScanning { _ in ScanResult(value: [cacheCandidate], issues: []) }
        )
        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [cacheCandidate]
        viewModel.selectedCandidateIDs = [cacheCandidate.id]
        viewModel.cleanupMode = .resetData

        let report = await viewModel.resetSelectedData(confirmation: "DELETE")

        XCTAssertEqual(report?.receipt.action, .appReset)
        XCTAssertFalse(report?.receipt.confirmationMatched ?? true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testResetKeepsAppSelectedRescansAndRecordsReceipt() async throws {
        let home = try temporaryDirectory(named: "reset-e2e")
        defer { try? FileManager.default.removeItem(at: home) }
        let appsRoot = home.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: appsRoot, withIntermediateDirectories: true)
        let appURL = try makeAppBundle(root: appsRoot, name: "Reset Fixture", bundleIdentifier: "com.example.reset-fixture")
        let cacheURL = home.appendingPathComponent("Library/Caches/com.example.reset-fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: cacheURL.appendingPathComponent("cache.db"))
        let receiptURL = home.appendingPathComponent("receipts.jsonl")
        let scanCounter = ScanCounter()
        let scanner = RelatedFileScanner(homeDirectory: home)
        let viewModel = ApplicationListViewModel(
            discoveryService: AppDiscoveryService(searchRoots: [appsRoot]),
            scanner: scanner,
            executor: removingExecutor(home: home),
            receiptStore: DeletionReceiptStore(fileURL: receiptURL),
            relatedFileScanning: RelatedFileScanning { app in
                scanCounter.increment()
                return await scanner.scanRelatedFilesWithCoverage(for: app)
            }
        )

        await viewModel.loadApps()
        await viewModel.scanSelectedApp()
        viewModel.cleanupMode = .resetData
        let report = await viewModel.resetSelectedData(confirmation: "RESET")

        XCTAssertEqual(report?.receipt.action, .appReset)
        XCTAssertTrue(report?.isFullySuccessful ?? false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertEqual(viewModel.selectedApp?.bundleURL.standardizedFileURL, appURL.standardizedFileURL)
        XCTAssertEqual(scanCounter.value, 2)
        XCTAssertTrue(viewModel.reviewCandidates.isEmpty)
        let receipts = try DeletionReceiptStore(fileURL: receiptURL).readReceipts()
        XCTAssertEqual(receipts.map(\.action), [.appReset])
        XCTAssertFalse(receipts[0].selectedCandidates.contains { $0.kind == .appBundle })
    }

    func testResetRefusesRunningApplication() async throws {
        let home = try temporaryDirectory(named: "reset-running")
        defer { try? FileManager.default.removeItem(at: home) }
        let appURL = try makeAppBundle(root: home, name: "Running Reset", bundleIdentifier: "com.example.running-reset")
        let cacheURL = home.appendingPathComponent("Library/Caches/com.example.running-reset", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let app = installedApp(at: appURL, name: "Running Reset", bundleIdentifier: "com.example.running-reset")
        let cacheCandidate = candidate(at: cacheURL, kind: .cache)
        let receiptStore = DeletionReceiptStore(fileURL: home.appendingPathComponent("receipts.jsonl"))
        let viewModel = ApplicationListViewModel(
            executor: removingExecutor(home: home),
            runningApplicationMonitor: RunningApplicationMonitor(isRunning: { _ in true }),
            receiptStore: receiptStore
        )
        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [cacheCandidate]
        viewModel.selectedCandidateIDs = [cacheCandidate.id]
        viewModel.cleanupMode = .resetData

        let report = await viewModel.resetSelectedData(confirmation: "RESET")

        XCTAssertNil(report)
        XCTAssertEqual(viewModel.errorMessage, "Quit Running Reset before resetting its data.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertTrue(try receiptStore.readReceipts().isEmpty)
    }

    func testResetReceiptWriteFailureDoesNotHideVerifiedResult() async throws {
        let home = try temporaryDirectory(named: "reset-receipt-failure")
        defer { try? FileManager.default.removeItem(at: home) }
        let appURL = try makeAppBundle(root: home, name: "Reset Receipt", bundleIdentifier: "com.example.reset-receipt")
        let cacheURL = home.appendingPathComponent("Library/Caches/com.example.reset-receipt", isDirectory: true)
        let receiptParent = home.appendingPathComponent("receipt-parent")
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: receiptParent)
        let app = installedApp(at: appURL, name: "Reset Receipt", bundleIdentifier: "com.example.reset-receipt")
        let cacheCandidate = candidate(at: cacheURL, kind: .cache)
        let viewModel = ApplicationListViewModel(
            executor: removingExecutor(home: home),
            receiptStore: DeletionReceiptStore(fileURL: receiptParent.appendingPathComponent("receipts.jsonl")),
            relatedFileScanning: RelatedFileScanning { _ in ScanResult(value: [], issues: []) }
        )
        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [cacheCandidate]
        viewModel.selectedCandidateIDs = [cacheCandidate.id]
        viewModel.cleanupMode = .resetData

        let report = await viewModel.resetSelectedData(confirmation: "RESET")

        XCTAssertTrue(report?.isFullySuccessful ?? false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertEqual(viewModel.selectedApp, app)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanResetTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    private func makeAppBundle(root: URL, name: String, bundleIdentifier: String) throws -> URL {
        let appURL = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleExecutable": name
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        return appURL
    }

    private func installedApp(at url: URL, name: String, bundleIdentifier: String) -> InstalledApp {
        InstalledApp(displayName: name, bundleIdentifier: bundleIdentifier, version: nil, executableName: name, bundleURL: url, iconIdentifier: nil, bundleSize: 1, lastOpenedAt: nil)
    }

    private func candidate(at url: URL, kind: RelatedFileKind, isProtected: Bool = false) -> RelatedFileCandidate {
        RelatedFileCandidate(
            url: url,
            kind: kind,
            size: 1,
            matchReason: "test",
            confidence: .high,
            safety: isProtected ? .risky : .safe,
            defaultSelected: !isProtected,
            requiresManualReview: isProtected,
            isProtected: isProtected
        )
    }

    private func removingExecutor(home: URL) -> DeletionExecutor {
        DeletionExecutor(
            fileRemover: DeletionFileRemover(
                trash: { try FileManager.default.removeItem(at: $0) },
                remove: { _ in throw CocoaError(.fileWriteNoPermission) }
            ),
            protectionPolicy: ProtectionPolicy(homeDirectory: home)
        )
    }
}

private final class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock { storage += 1 }
    }
}
