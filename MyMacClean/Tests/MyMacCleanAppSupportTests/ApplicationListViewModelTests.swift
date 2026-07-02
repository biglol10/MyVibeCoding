import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class ApplicationListViewModelTests: XCTestCase {
    func testDisposableAppEndToEndDeletionScansDeletesAndRecordsReceipt() async throws {
        let home = try temporaryDirectory(named: "e2e-delete-home")
        defer { try? FileManager.default.removeItem(at: home) }
        let appsRoot = home.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: appsRoot, withIntermediateDirectories: true)
        let appURL = try makeAppBundle(
            root: appsRoot,
            name: "Workflow Delete Fixture",
            bundleIdentifier: "com.example.workflow-delete"
        )
        let supportURL = home.appendingPathComponent("Library/Application Support/Workflow Delete Fixture", isDirectory: true)
        let cacheURL = home.appendingPathComponent("Library/Caches/com.example.workflow-delete", isDirectory: true)
        let prefsURL = home.appendingPathComponent("Library/Preferences/com.example.workflow-delete.plist")
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("state".utf8).write(to: supportURL.appendingPathComponent("state.db"))
        try Data("cache".utf8).write(to: cacheURL.appendingPathComponent("cache.bin"))
        try Data("prefs".utf8).write(to: prefsURL)
        let receiptURL = home.appendingPathComponent("receipts.jsonl")
        let viewModel = ApplicationListViewModel(
            discoveryService: AppDiscoveryService(searchRoots: [appsRoot]),
            scanner: RelatedFileScanner(homeDirectory: home),
            receiptStore: DeletionReceiptStore(fileURL: receiptURL)
        )

        await viewModel.loadApps()
        await viewModel.scanSelectedApp()
        await viewModel.deleteConfirmedItems(confirmation: "DELETE", mode: .permanent)

        XCTAssertEqual(viewModel.apps, [])
        XCTAssertNil(viewModel.selectedApp)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: supportURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: prefsURL.path))

        let receipts = try DeletionReceiptStore(fileURL: receiptURL).readReceipts()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].appName, "Workflow Delete Fixture")
        XCTAssertEqual(receipts[0].selectedCandidates.map { normalizedPath($0.path) }.sorted(), [
            appURL.path,
            cacheURL.path,
            prefsURL.path,
            supportURL.path
        ].map(normalizedPath).sorted())
        XCTAssertEqual(Set(receipts[0].verificationResults.map(\.status)), [.deleted])
    }

    func testTracksWhetherApplicationsHaveLoaded() async throws {
        let root = try temporaryDirectory(named: "app-load-state")
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeAppBundle(root: root, name: "First", bundleIdentifier: "com.example.first")
        let viewModel = ApplicationListViewModel(
            discoveryService: AppDiscoveryService(searchRoots: [root])
        )

        XCTAssertFalse(viewModel.hasLoadedApps)

        await viewModel.loadApps()

        XCTAssertTrue(viewModel.hasLoadedApps)
        XCTAssertEqual(viewModel.apps.count, 1)
    }

    func testLoadAppsExcludesCurrentApplicationFromDeletableList() async throws {
        let root = try temporaryDirectory(named: "app-excludes-self")
        defer { try? FileManager.default.removeItem(at: root) }
        let selfAppURL = try makeAppBundle(root: root, name: "MyMacClean", bundleIdentifier: "com.local.mymacclean")
        _ = try makeAppBundle(root: root, name: "Other", bundleIdentifier: "com.example.other")
        let viewModel = ApplicationListViewModel(
            discoveryService: AppDiscoveryService(searchRoots: [root]),
            excludedBundleIdentifiers: ["com.local.mymacclean"],
            excludedBundleURLs: [selfAppURL]
        )

        await viewModel.loadApps()

        XCTAssertEqual(viewModel.apps.map(\.bundleIdentifier), ["com.example.other"])
        XCTAssertEqual(viewModel.selectedApp?.bundleIdentifier, "com.example.other")
    }

    func testSelectingDifferentAppClearsStaleScanResults() {
        let first = InstalledApp(
            displayName: "First",
            bundleIdentifier: "com.example.first",
            version: nil,
            executableName: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/First.app"),
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let second = InstalledApp(
            displayName: "Second",
            bundleIdentifier: "com.example.second",
            version: nil,
            executableName: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Second.app"),
            iconIdentifier: nil,
            bundleSize: 2,
            lastOpenedAt: nil
        )
        let staleCandidate = RelatedFileCandidate(
            url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.example.first"),
            kind: .cache,
            size: 10,
            matchReason: "bundle identifier match",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel()

        viewModel.apps = [first, second]
        viewModel.selectApp(first)
        viewModel.candidates = [staleCandidate]
        viewModel.selectedCandidateIDs = [staleCandidate.id]
        viewModel.selectApp(second)

        XCTAssertEqual(viewModel.selectedApp, second)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
    }

    func testRefreshAppsKeepsSelectedAppWhenStillInstalled() async throws {
        let root = try temporaryDirectory(named: "refresh-keeps-selection")
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = try makeAppBundle(root: root, name: "First", bundleIdentifier: "com.example.first")
        let secondURL = try makeAppBundle(root: root, name: "Second", bundleIdentifier: "com.example.second")
        let staleCandidate = RelatedFileCandidate(
            url: root.appendingPathComponent("Library/Caches/com.example.second"),
            kind: .cache,
            size: 10,
            matchReason: "bundle identifier match",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel(
            discoveryService: AppDiscoveryService(searchRoots: [root])
        )

        await viewModel.loadApps()
        viewModel.selectApp(viewModel.apps.first { $0.bundleIdentifier == "com.example.second" })
        let selectedIDBeforeRefresh = try XCTUnwrap(viewModel.selectedApp?.id)
        viewModel.candidates = [staleCandidate]
        viewModel.selectedCandidateIDs = [staleCandidate.id]

        await viewModel.refreshApps()

        XCTAssertEqual(Set(viewModel.apps.map { normalizedURL($0.bundleURL) }), [normalizedURL(firstURL), normalizedURL(secondURL)])
        XCTAssertEqual(viewModel.selectedApp?.bundleIdentifier, "com.example.second")
        XCTAssertEqual(viewModel.selectedApp.map { normalizedURL($0.bundleURL) }, normalizedURL(secondURL))
        XCTAssertNotEqual(viewModel.selectedApp?.id, selectedIDBeforeRefresh)
        XCTAssertEqual(viewModel.candidates, [staleCandidate])
        XCTAssertEqual(viewModel.selectedCandidateIDs, [staleCandidate.id])
    }

    func testRefreshAppsClearsSelectionWhenUpdatedAppNoLongerMatchesSearch() async throws {
        let root = try temporaryDirectory(named: "refresh-clears-search-hidden-selection")
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = try makeAppBundle(root: root, name: "StableBundle", bundleIdentifier: "com.example.stable")
        try rewriteAppBundleInfo(appURL: appURL, displayName: "Old Target", bundleIdentifier: "com.example.stable")
        let staleCandidate = RelatedFileCandidate(
            url: root.appendingPathComponent("Library/Caches/com.example.stable"),
            kind: .cache,
            size: 10,
            matchReason: "bundle identifier match",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel(
            discoveryService: AppDiscoveryService(searchRoots: [root])
        )

        await viewModel.loadApps()
        viewModel.appSearchText = "old target"
        viewModel.selectApp(viewModel.visibleApps.first)
        viewModel.candidates = [staleCandidate]
        viewModel.selectedCandidateIDs = [staleCandidate.id]
        try rewriteAppBundleInfo(appURL: appURL, displayName: "New Target", bundleIdentifier: "com.example.stable")

        await viewModel.refreshApps()

        XCTAssertTrue(viewModel.visibleApps.isEmpty)
        XCTAssertNil(viewModel.selectedApp)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
    }

    func testRefreshAppsClearsReviewStateWhenSelectedAppWasRemoved() async throws {
        let root = try temporaryDirectory(named: "refresh-clears-removed-selection")
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = try makeAppBundle(root: root, name: "First", bundleIdentifier: "com.example.first")
        let secondURL = try makeAppBundle(root: root, name: "Second", bundleIdentifier: "com.example.second")
        let staleCandidate = RelatedFileCandidate(
            url: root.appendingPathComponent("Library/Caches/com.example.second"),
            kind: .cache,
            size: 10,
            matchReason: "bundle identifier match",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel(
            discoveryService: AppDiscoveryService(searchRoots: [root])
        )

        await viewModel.loadApps()
        viewModel.selectApp(viewModel.apps.first { $0.bundleIdentifier == "com.example.second" })
        viewModel.candidates = [staleCandidate]
        viewModel.selectedCandidateIDs = [staleCandidate.id]
        viewModel.deletionResults = [
            DeletionItemResult(path: staleCandidate.url.path, success: true, errorMessage: nil)
        ]
        try FileManager.default.removeItem(at: secondURL)

        await viewModel.refreshApps()

        XCTAssertEqual(viewModel.apps.map { normalizedURL($0.bundleURL) }, [normalizedURL(firstURL)])
        XCTAssertNil(viewModel.selectedApp)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
        XCTAssertTrue(viewModel.deletionResults.isEmpty)
        XCTAssertNil(viewModel.deletionReport)
    }

    func testAppSearchFiltersByNameBundleIdentifierAndPath() {
        let viewModel = ApplicationListViewModel()
        let cursor = InstalledApp(
            displayName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            version: nil,
            executableName: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Cursor.app"),
            iconIdentifier: nil,
            bundleSize: 10,
            lastOpenedAt: nil
        )
        let chrome = InstalledApp(
            displayName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            version: nil,
            executableName: nil,
            bundleURL: URL(fileURLWithPath: "/Users/me/Applications/Google Chrome.app"),
            iconIdentifier: nil,
            bundleSize: 20,
            lastOpenedAt: nil
        )

        viewModel.apps = [cursor, chrome]

        viewModel.appSearchText = "desktop"
        XCTAssertEqual(viewModel.visibleApps, [cursor])

        viewModel.appSearchText = "google"
        XCTAssertEqual(viewModel.visibleApps, [chrome])

        viewModel.appSearchText = "users/me"
        XCTAssertEqual(viewModel.visibleApps, [chrome])
    }

    func testAppFilterClearsReviewStateWhenSelectedAppIsHidden() {
        let viewModel = ApplicationListViewModel()
        let systemApp = InstalledApp(
            displayName: "System App",
            bundleIdentifier: "com.example.system",
            version: nil,
            executableName: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/System App.app"),
            iconIdentifier: nil,
            bundleSize: 10,
            lastOpenedAt: nil
        )
        let userApp = InstalledApp(
            displayName: "User App",
            bundleIdentifier: "com.example.user",
            version: nil,
            executableName: nil,
            bundleURL: URL(fileURLWithPath: "/Users/me/Applications/User App.app"),
            iconIdentifier: nil,
            bundleSize: 20,
            lastOpenedAt: nil
        )
        let staleCandidate = RelatedFileCandidate(
            url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.example.system"),
            kind: .cache,
            size: 1,
            matchReason: "bundle identifier match",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )

        viewModel.apps = [systemApp, userApp]
        viewModel.selectApp(systemApp)
        viewModel.candidates = [staleCandidate]
        viewModel.selectedCandidateIDs = [staleCandidate.id]

        viewModel.appFilter = .userApplications

        XCTAssertEqual(viewModel.visibleApps, [userApp])
        XCTAssertNil(viewModel.selectedApp)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
    }

    func testAppSortBySizeKeepsVisibleSelectionStable() {
        let viewModel = ApplicationListViewModel()
        let small = InstalledApp(
            displayName: "Small",
            bundleIdentifier: "com.example.small",
            version: nil,
            executableName: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Small.app"),
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let large = InstalledApp(
            displayName: "Large",
            bundleIdentifier: "com.example.large",
            version: nil,
            executableName: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Large.app"),
            iconIdentifier: nil,
            bundleSize: 100,
            lastOpenedAt: nil
        )

        viewModel.apps = [small, large]
        viewModel.selectApp(small)

        viewModel.appSort = .sizeDescending

        XCTAssertEqual(viewModel.visibleApps, [large, small])
        XCTAssertEqual(viewModel.selectedApp, small)
    }

    func testSuccessfulDeletionRemovesDeletedAppAndClearsReviewState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanAppSupportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Cursor.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.todesktop.230313mzl4w4u92", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        let deletedApp = InstalledApp(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            displayName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let remainingApp = InstalledApp(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            displayName: "Remaining",
            bundleIdentifier: "com.example.remaining",
            version: nil,
            executableName: nil,
            bundleURL: root.appendingPathComponent("Remaining.app", isDirectory: true),
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let appCandidate = RelatedFileCandidate(
            url: appURL,
            kind: .appBundle,
            size: 1,
            matchReason: "app bundle",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let cacheCandidate = RelatedFileCandidate(
            url: cacheURL,
            kind: .cache,
            size: 1,
            matchReason: "bundle identifier match",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel(receiptStore: DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl")))

        viewModel.apps = [deletedApp, remainingApp]
        viewModel.selectApp(deletedApp)
        viewModel.candidates = [appCandidate, cacheCandidate]
        viewModel.selectedCandidateIDs = [appCandidate.id, cacheCandidate.id]

        await viewModel.deleteConfirmedItems(confirmation: "DELETE")

        XCTAssertFalse(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertEqual(viewModel.apps, [remainingApp])
        XCTAssertNil(viewModel.selectedApp)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
        XCTAssertTrue(viewModel.deletionResults.isEmpty)
        XCTAssertNil(viewModel.deletionReport)
    }

    func testPartialAppDeletionRemovesDeletedBundleFromListAndReportsRemainingItems() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanPartialDeletionTests-\(UUID().uuidString)", isDirectory: true)
        let appURL = root.appendingPathComponent("Partial.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.example.partial", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let failingCacheURL = cacheURL.resolvingSymlinksInPath().standardizedFileURL
        let remover = DeletionFileRemover(
            trash: { url in
                if url.resolvingSymlinksInPath().standardizedFileURL == failingCacheURL {
                    throw CocoaError(.fileWriteNoPermission)
                }
                try FileManager.default.removeItem(at: url)
            },
            remove: { url in
                if url.resolvingSymlinksInPath().standardizedFileURL == failingCacheURL {
                    throw CocoaError(.fileWriteNoPermission)
                }
                try FileManager.default.removeItem(at: url)
            }
        )

        let deletedApp = InstalledApp(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            displayName: "Partial",
            bundleIdentifier: "com.example.partial",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let remainingApp = InstalledApp(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            displayName: "Remaining",
            bundleIdentifier: "com.example.remaining",
            version: nil,
            executableName: nil,
            bundleURL: root.appendingPathComponent("Remaining.app", isDirectory: true),
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let appCandidate = RelatedFileCandidate(
            url: appURL,
            kind: .appBundle,
            size: 1,
            matchReason: "app bundle",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let cacheCandidate = RelatedFileCandidate(
            url: cacheURL,
            kind: .cache,
            size: 1,
            matchReason: "bundle identifier match",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel(
            executor: DeletionExecutor(fileRemover: remover),
            receiptStore: DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        )

        viewModel.apps = [deletedApp, remainingApp]
        viewModel.selectApp(deletedApp)
        viewModel.candidates = [appCandidate, cacheCandidate]
        viewModel.selectedCandidateIDs = [appCandidate.id, cacheCandidate.id]

        await viewModel.deleteConfirmedItems(confirmation: "DELETE", mode: .permanent)

        XCTAssertFalse(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertEqual(viewModel.apps, [remainingApp])
        XCTAssertNil(viewModel.selectedApp)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
        XCTAssertTrue(viewModel.deletionResults.isEmpty)
        XCTAssertEqual(viewModel.deletionReport?.statusTitle, "Deleted with remaining items")
        XCTAssertEqual(viewModel.deletionReport?.deletedCount, 1)
        XCTAssertEqual(viewModel.deletionReport?.remainingPaths, [cacheURL.path])
    }

    func testSuccessfulAppDeletionRecordsReceiptWithoutLeavingInspectorReport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanReportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Report.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        let receiptURL = root.appendingPathComponent("receipts.jsonl")
        let app = InstalledApp(
            displayName: "Report",
            bundleIdentifier: "com.example.report",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let candidate = RelatedFileCandidate(
            url: appURL,
            kind: .appBundle,
            size: 1,
            matchReason: "app bundle",
            confidence: .high,
            safety: .safe,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel(receiptStore: DeletionReceiptStore(fileURL: receiptURL))

        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [candidate]
        viewModel.selectedCandidateIDs = [candidate.id]

        await viewModel.deleteConfirmedItems(confirmation: "DELETE")

        XCTAssertNil(viewModel.selectedApp)
        XCTAssertNil(viewModel.deletionReport)
        XCTAssertEqual(try DeletionReceiptStore(fileURL: receiptURL).readReceipts().count, 1)
    }

    func testSuccessfulRelatedFileDeletionKeepsSelectedAppAndReport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanRelatedFileReportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Report.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.example.report", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let receiptURL = root.appendingPathComponent("receipts.jsonl")
        let app = InstalledApp(
            displayName: "Report",
            bundleIdentifier: "com.example.report",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let candidate = RelatedFileCandidate(
            url: cacheURL,
            kind: .cache,
            size: 1,
            matchReason: "bundle identifier match",
            confidence: .high,
            safety: .safe,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel(receiptStore: DeletionReceiptStore(fileURL: receiptURL))

        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [candidate]
        viewModel.selectedCandidateIDs = [candidate.id]

        await viewModel.deleteConfirmedItems(confirmation: "DELETE")

        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertEqual(viewModel.selectedApp, app)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertEqual(viewModel.deletionReport?.statusTitle, "Deleted and verified")
        XCTAssertEqual(try DeletionReceiptStore(fileURL: receiptURL).readReceipts().count, 1)
    }

    func testSuccessfulDeletionClearsPreviousErrorMessage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanClearDeleteErrorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Clear Error.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.example.clear-error", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let receiptURL = root.appendingPathComponent("receipts.jsonl")
        let app = InstalledApp(
            displayName: "Clear Error",
            bundleIdentifier: "com.example.clear-error",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let candidate = RelatedFileCandidate(
            url: cacheURL,
            kind: .cache,
            size: 1,
            matchReason: "bundle identifier match",
            confidence: .high,
            safety: .safe,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel(receiptStore: DeletionReceiptStore(fileURL: receiptURL))

        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [candidate]
        viewModel.selectedCandidateIDs = [candidate.id]
        viewModel.errorMessage = "Previous deletion failed"

        await viewModel.deleteConfirmedItems(confirmation: "DELETE")

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertEqual(viewModel.deletionReport?.statusTitle, "Deleted and verified")
    }

    func testDeletionReportsReceiptWriteFailureWithoutHidingDeletionResult() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanReceiptFailureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Receipt Failure.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.example.receipt-failure", isDirectory: true)
        let receiptParentFileURL = root.appendingPathComponent("receipt-parent")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: receiptParentFileURL)
        let app = InstalledApp(
            displayName: "Receipt Failure",
            bundleIdentifier: "com.example.receipt-failure",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let candidate = RelatedFileCandidate(
            url: cacheURL,
            kind: .cache,
            size: 1,
            matchReason: "bundle identifier match",
            confidence: .high,
            safety: .safe,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel(
            receiptStore: DeletionReceiptStore(fileURL: receiptParentFileURL.appendingPathComponent("receipts.jsonl"))
        )

        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [candidate]
        viewModel.selectedCandidateIDs = [candidate.id]

        await viewModel.deleteConfirmedItems(confirmation: "DELETE")

        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertEqual(viewModel.selectedApp, app)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertEqual(viewModel.deletionReport?.statusTitle, "Deleted and verified")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testDeleteConfirmedItemsIgnoresRequestsWhileDeletionIsAlreadyRunning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanDuplicateDeleteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Duplicate.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.example.duplicate", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let app = InstalledApp(
            displayName: "Duplicate",
            bundleIdentifier: "com.example.duplicate",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let candidate = RelatedFileCandidate(
            url: cacheURL,
            kind: .cache,
            size: 1,
            matchReason: "bundle identifier match",
            confidence: .high,
            safety: .safe,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel(receiptStore: DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl")))

        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [candidate]
        viewModel.selectedCandidateIDs = [candidate.id]
        viewModel.isDeleting = true

        await viewModel.deleteConfirmedItems(confirmation: "DELETE")

        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertEqual(viewModel.selectedCandidateIDs, [candidate.id])
        XCTAssertNil(viewModel.deletionReport)
    }

    func testDeleteConfirmedItemsRefusesRunningApplication() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanRunningAppDeleteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Running.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.example.running", isDirectory: true)
        let receiptURL = root.appendingPathComponent("receipts.jsonl")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let app = InstalledApp(
            displayName: "Running",
            bundleIdentifier: "com.example.running",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let candidate = RelatedFileCandidate(
            url: cacheURL,
            kind: .cache,
            size: 1,
            matchReason: "bundle identifier match",
            confidence: .high,
            safety: .safe,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let store = DeletionReceiptStore(fileURL: receiptURL)
        let viewModel = ApplicationListViewModel(
            runningApplicationMonitor: RunningApplicationMonitor(isRunning: { _ in true }),
            receiptStore: store
        )

        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [candidate]
        viewModel.selectedCandidateIDs = [candidate.id]

        await viewModel.deleteConfirmedItems(confirmation: "DELETE")

        XCTAssertEqual(viewModel.errorMessage, "Quit Running before deleting it.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertEqual(viewModel.selectedCandidateIDs, [candidate.id])
        XCTAssertNil(viewModel.deletionReport)
        XCTAssertTrue(try store.readReceipts().isEmpty)
        XCTAssertFalse(viewModel.isDeleting)
    }

    func testDeleteConfirmedItemsShowsActionableMessageWhenOnlyProtectedItemsAreSelected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanProtectedSelectionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Protected.app", isDirectory: true)
        let protectedURL = root.appendingPathComponent("Documents/Protected Export", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: protectedURL, withIntermediateDirectories: true)
        let app = InstalledApp(
            displayName: "Protected",
            bundleIdentifier: "com.example.protected",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let protectedCandidate = RelatedFileCandidate(
            url: protectedURL,
            kind: .unknown,
            size: 1,
            matchReason: "manual review",
            confidence: .low,
            safety: .risky,
            defaultSelected: false,
            requiresManualReview: true,
            isProtected: true
        )
        let viewModel = ApplicationListViewModel(receiptStore: DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl")))

        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [protectedCandidate]
        viewModel.selectedCandidateIDs = [protectedCandidate.id]
        viewModel.deletionResults = [
            DeletionItemResult(path: "/tmp/old-cache", success: true, errorMessage: nil)
        ]
        viewModel.deletionReport = DeletionReportViewModel(receipt: DeletionReceipt(
            appName: "Old App",
            bundleIdentifier: "com.example.old",
            bundlePath: "/Applications/Old.app",
            action: .uninstall,
            selectedCandidates: [],
            executionResults: [],
            verificationResults: [
                DeletionVerificationResult(path: "/tmp/old-cache", status: .deleted, errorMessage: nil)
            ],
            confirmationMatched: true
        ))

        await viewModel.deleteConfirmedItems(confirmation: "DELETE")

        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedURL.path))
        XCTAssertEqual(viewModel.errorMessage, "Select at least one deletable item.")
        XCTAssertTrue(viewModel.deletionResults.isEmpty)
        XCTAssertNil(viewModel.deletionReport)
        XCTAssertFalse(viewModel.isDeleting)
    }

    func testScanningSelectedAppClearsPreviousDeletionReport() async throws {
        let home = try temporaryDirectory(named: "scan-clears-report")
        defer { try? FileManager.default.removeItem(at: home) }
        let appURL = try makeAppBundle(root: home, name: "Scan Target", bundleIdentifier: "com.example.scan-target")
        let app = InstalledApp(
            displayName: "Scan Target",
            bundleIdentifier: "com.example.scan-target",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let viewModel = ApplicationListViewModel(scanner: RelatedFileScanner(homeDirectory: home))

        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.deletionResults = [
            DeletionItemResult(path: "/tmp/old-cache", success: true, errorMessage: nil)
        ]
        viewModel.deletionReport = DeletionReportViewModel(receipt: DeletionReceipt(
            appName: "Old App",
            bundleIdentifier: "com.example.old",
            bundlePath: "/Applications/Old.app",
            action: .uninstall,
            selectedCandidates: [],
            executionResults: [],
            verificationResults: [
                DeletionVerificationResult(path: "/tmp/old-cache", status: .deleted, errorMessage: nil)
            ],
            confirmationMatched: true
        ))

        await viewModel.scanSelectedApp()

        XCTAssertFalse(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.deletionResults.isEmpty)
        XCTAssertNil(viewModel.deletionReport)
    }

    func testSuccessfulSelectedAppScanClearsPreviousErrorMessage() async throws {
        let home = try temporaryDirectory(named: "scan-clears-error")
        defer { try? FileManager.default.removeItem(at: home) }
        let appURL = try makeAppBundle(root: home, name: "Scan Target", bundleIdentifier: "com.example.scan-target")
        let cacheURL = home.appendingPathComponent("Library/Caches/com.example.scan-target", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let app = InstalledApp(
            displayName: "Scan Target",
            bundleIdentifier: "com.example.scan-target",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
        let viewModel = ApplicationListViewModel(scanner: RelatedFileScanner(homeDirectory: home))
        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.errorMessage = "Previous scan failed"

        await viewModel.scanSelectedApp()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.candidates.isEmpty)
    }

    func testSelectedAppScanSkipsUnreadableRootsAndClearsPreviousCandidates() async throws {
        let home = try temporaryDirectory(named: "failed-scan-clears-candidates")
        defer { try? FileManager.default.removeItem(at: home) }
        let appURL = try makeAppBundle(root: home, name: "Broken Scan", bundleIdentifier: "com.example.broken-scan")
        let libraryURL = home.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: libraryURL.appendingPathComponent("Caches"))
        let app = InstalledApp(
            displayName: "Broken Scan",
            bundleIdentifier: "com.example.broken-scan",
            version: nil,
            executableName: nil,
            bundleURL: appURL,
            iconIdentifier: nil,
            bundleSize: 1,
            lastOpenedAt: nil
        )
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
        let viewModel = ApplicationListViewModel(scanner: RelatedFileScanner(homeDirectory: home))

        viewModel.apps = [app]
        viewModel.selectApp(app)
        viewModel.candidates = [staleCandidate]
        viewModel.selectedCandidateIDs = [staleCandidate.id]

        await viewModel.scanSelectedApp()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.candidates.contains { $0.url == appURL })
        XCTAssertFalse(viewModel.selectedCandidateIDs.contains(staleCandidate.id))
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanAppSupportTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    private func makeAppBundle(root: URL, name: String, bundleIdentifier: String) throws -> URL {
        let appURL = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleShortVersionString": "1.0",
            "CFBundleExecutable": name
        ]
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: infoURL)
        try Data(repeating: 1, count: 3).write(to: macOSURL.appendingPathComponent(name))
        return appURL
    }

    private func rewriteAppBundleInfo(appURL: URL, displayName: String, bundleIdentifier: String) throws {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        let info: [String: Any] = [
            "CFBundleName": displayName,
            "CFBundleDisplayName": displayName,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleShortVersionString": "1.0",
            "CFBundleExecutable": appURL.deletingPathExtension().lastPathComponent
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: infoURL)
    }

    private func normalizedURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func normalizedPath(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if standardized.hasPrefix("/private/var/") {
            return String(standardized.dropFirst("/private".count))
        }
        return standardized
    }
}
