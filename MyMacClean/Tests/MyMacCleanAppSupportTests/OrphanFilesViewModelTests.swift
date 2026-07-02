import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class OrphanFilesViewModelTests: XCTestCase {
    func testTracksWhetherLeftoverScanHasRun() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanScanState-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let viewModel = OrphanFilesViewModel(homeDirectory: home, installedApps: [])

        XCTAssertFalse(viewModel.hasScanned)

        await viewModel.loadGroups()

        XCTAssertTrue(viewModel.hasScanned)
    }

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

    func testUpdatingInstalledAppsClearsStaleOrphanScanResults() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanInstalledAppsRefresh-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let orphan = home.appendingPathComponent("Library/Caches/com.example.returned", isDirectory: true)
        let appURL = home.appendingPathComponent("Applications/Returned.app", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        let installedApp = InstalledApp(
            displayName: "Returned",
            bundleIdentifier: "com.example.returned",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let viewModel = OrphanFilesViewModel(homeDirectory: home, installedApps: [])

        await viewModel.loadGroups()
        viewModel.selectedCandidateIDs = Set(viewModel.groups.flatMap(\.candidates).map(\.id))
        viewModel.deletionReport = DeletionReportViewModel(receipt: DeletionReceipt(
            appName: "Orphan Files",
            bundleIdentifier: nil,
            bundlePath: home.path,
            action: .orphanCleanup,
            selectedCandidates: [],
            executionResults: [],
            verificationResults: [
                DeletionVerificationResult(path: orphan.path, status: .stillExists, errorMessage: nil)
            ],
            confirmationMatched: true
        ))

        viewModel.updateInstalledApps([installedApp])

        XCTAssertFalse(viewModel.hasScanned)
        XCTAssertTrue(viewModel.groups.isEmpty)
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
        XCTAssertNil(viewModel.deletionReport)
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

    func testDeleteSelectedLeftoversReportsReceiptWriteFailureWithoutHidingDeletionResult() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanReceiptFailure-\(UUID().uuidString)", isDirectory: true)
        let receiptRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanReceiptParentFailure-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: receiptRoot)
        }
        let orphan = home.appendingPathComponent("Library/Caches/com.example.deleted", isDirectory: true)
        let receiptParentFileURL = receiptRoot.appendingPathComponent("receipt-parent")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: receiptRoot, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: receiptParentFileURL)
        let store = DeletionReceiptStore(fileURL: receiptParentFileURL.appendingPathComponent("receipts.jsonl"))
        let viewModel = OrphanFilesViewModel(homeDirectory: home, installedApps: [], receiptStore: store)

        await viewModel.loadGroups()
        viewModel.selectedCandidateIDs = Set(viewModel.groups.flatMap(\.candidates).map(\.id))
        await viewModel.deleteSelectedLeftovers(confirmation: "DELETE")

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(viewModel.groups.isEmpty)
        XCTAssertEqual(viewModel.deletionReport?.statusTitle, "Deleted and verified")
        XCTAssertTrue(viewModel.errorMessage?.hasPrefix("Could not save deletion history:") == true)
    }

    func testDeleteSelectedLeftoversClearsPreviousErrorMessageOnSuccess() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanClearDeleteError-\(UUID().uuidString)", isDirectory: true)
        let receiptRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanClearDeleteErrorReceipt-\(UUID().uuidString)", isDirectory: true)
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
        viewModel.errorMessage = "Previous deletion failed"

        await viewModel.deleteSelectedLeftovers(confirmation: "DELETE")

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertEqual(viewModel.deletionReport?.statusTitle, "Deleted and verified")
    }

    func testDeleteSelectedLeftoversIgnoresRequestsWhileDeletionIsAlreadyRunning() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanDuplicateDelete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let orphan = home.appendingPathComponent("Library/Caches/com.example.deleted", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        let viewModel = OrphanFilesViewModel(homeDirectory: home, installedApps: [])

        await viewModel.loadGroups()
        viewModel.selectedCandidateIDs = Set(viewModel.groups.flatMap(\.candidates).map(\.id))
        viewModel.isDeleting = true

        await viewModel.deleteSelectedLeftovers(confirmation: "DELETE")

        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertFalse(viewModel.groups.isEmpty)
        XCTAssertNil(viewModel.deletionReport)
    }

    func testDeleteSelectedLeftoversShowsActionableMessageWhenSelectionIsEmpty() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanEmptyDelete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let orphan = home.appendingPathComponent("Library/Caches/com.example.deleted", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        let viewModel = OrphanFilesViewModel(homeDirectory: home, installedApps: [])

        await viewModel.loadGroups()
        viewModel.selectedCandidateIDs = []
        viewModel.deletionReport = DeletionReportViewModel(receipt: DeletionReceipt(
            appName: "Orphan Files",
            bundleIdentifier: nil,
            bundlePath: home.path,
            action: .orphanCleanup,
            selectedCandidates: [],
            executionResults: [],
            verificationResults: [
                DeletionVerificationResult(path: "/tmp/old-orphan", status: .deleted, errorMessage: nil)
            ],
            confirmationMatched: true
        ))

        await viewModel.deleteSelectedLeftovers(confirmation: "DELETE")

        XCTAssertEqual(viewModel.errorMessage, "Select at least one deletable item.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertNil(viewModel.deletionReport)
        XCTAssertFalse(viewModel.isDeleting)
    }

    func testDeleteSelectedLeftoversRejectsProtectedCandidatesEvenIfSelected() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanProtectedDelete-\(UUID().uuidString)", isDirectory: true)
        let receiptRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanProtectedReceipt-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: receiptRoot)
        }
        let protectedURL = home.appendingPathComponent("Documents/Important Export", isDirectory: true)
        try FileManager.default.createDirectory(at: protectedURL, withIntermediateDirectories: true)
        let protectedCandidate = RelatedFileCandidate(
            url: protectedURL,
            kind: .unknown,
            size: 1,
            matchReason: "stale protected candidate",
            confidence: .low,
            safety: .risky,
            defaultSelected: false,
            requiresManualReview: true,
            isProtected: true
        )
        let group = OrphanFileGroup(
            inferredName: "Important Export",
            inferredIdentifier: "important-export",
            candidates: [protectedCandidate]
        )
        let store = DeletionReceiptStore(fileURL: receiptRoot.appendingPathComponent("receipts.jsonl"))
        let viewModel = OrphanFilesViewModel(homeDirectory: home, installedApps: [], receiptStore: store)
        viewModel.groups = [group]
        viewModel.selectedCandidateIDs = [protectedCandidate.id]

        await viewModel.deleteSelectedLeftovers(confirmation: "DELETE")

        XCTAssertEqual(viewModel.errorMessage, "Select at least one deletable item.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedURL.path))
        XCTAssertNil(viewModel.deletionReport)
        XCTAssertTrue(try store.readReceipts().isEmpty)
        XCTAssertFalse(viewModel.isDeleting)
    }

    func testLoadGroupsClearsPreviousDeletionReport() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanClearReport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let orphan = home.appendingPathComponent("Library/Caches/com.example.deleted", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        let viewModel = OrphanFilesViewModel(homeDirectory: home, installedApps: [])
        viewModel.deletionReport = DeletionReportViewModel(receipt: DeletionReceipt(
            appName: "Orphan Files",
            bundleIdentifier: nil,
            bundlePath: home.path,
            action: .orphanCleanup,
            selectedCandidates: [],
            executionResults: [],
            verificationResults: [
                DeletionVerificationResult(path: "/tmp/old-orphan", status: .deleted, errorMessage: nil)
            ],
            confirmationMatched: true
        ))

        await viewModel.loadGroups()

        XCTAssertEqual(viewModel.groups.map(\.inferredIdentifier), ["com.example.deleted"])
        XCTAssertNil(viewModel.deletionReport)
    }

    func testSuccessfulLoadGroupsClearsPreviousErrorMessage() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanClearsError-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let orphan = home.appendingPathComponent("Library/Caches/com.example.deleted", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        let viewModel = OrphanFilesViewModel(homeDirectory: home, installedApps: [])
        viewModel.errorMessage = "Previous scan failed"

        await viewModel.loadGroups()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.groups.map(\.inferredIdentifier), ["com.example.deleted"])
    }

    func testLoadGroupsSkipsUnreadableRootsAndClearsPreviousSelection() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanOrphanFailedScan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let libraryURL = home.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: libraryURL.appendingPathComponent("Caches"))
        let staleCandidate = RelatedFileCandidate(
            url: home.appendingPathComponent("Library/Logs/com.example.old", isDirectory: true),
            kind: .log,
            size: 1,
            matchReason: "stale",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let staleGroup = OrphanFileGroup(
            inferredName: "com.example.old",
            inferredIdentifier: "com.example.old",
            candidates: [staleCandidate]
        )
        let viewModel = OrphanFilesViewModel(homeDirectory: home, installedApps: [])
        viewModel.groups = [staleGroup]
        viewModel.selectedCandidateIDs = [staleCandidate.id]

        await viewModel.loadGroups()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.groups.isEmpty)
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
    }
}
