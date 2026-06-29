import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
final class ExplorerPermissionRecoveryTests: XCTestCase {
    func testNavigationPermissionErrorRecordsChooseFolderRecoveryTarget() async {
        let deniedURL = URL(fileURLWithPath: "/tmp/denied", isDirectory: true)
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            fileSystemService: DenyingFileSystemService(deniedURL: deniedURL),
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: InMemoryBookmarkStore(),
            folderAccessService: StubFolderAccessService(result: .cancelled)
        )

        await store.navigate(to: deniedURL)

        XCTAssertEqual(store.visibleErrorGuidance?.recoveryAction, .chooseFolder)
        XCTAssertEqual(store.pendingPermissionRecoveryPath, deniedURL.standardizedFileURL.path)
    }

    func testChooseFolderCancellationLeavesGrantListUnchanged() async {
        let bookmarkStore = InMemoryBookmarkStore()
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: bookmarkStore,
            folderAccessService: StubFolderAccessService(result: .cancelled)
        )

        await store.chooseFolderForAccess()

        XCTAssertEqual(store.grantedFolderSummaries, [])
    }

    func testChooseFolderGrantSavesGrantAndPublishesSummary() async throws {
        let url = URL(fileURLWithPath: "/tmp/granted", isDirectory: true)
        let grant = FolderAccessGrant(url: url, bookmarkData: Data([1]))
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: InMemoryBookmarkStore(),
            folderAccessService: StubFolderAccessService(
                result: .granted(grant, ResolvedFolderAccess(url: url, isStale: false, didStartAccessing: true))
            )
        )

        await store.chooseFolderForAccess()

        XCTAssertEqual(store.grantedFolderSummaries.map(\.displayPath), [url.standardizedFileURL.path])
    }

    func testSandboxedInitResolvesPersistedGrantsAndPublishesAvailability() {
        let url = URL(fileURLWithPath: "/tmp/persisted-grant", isDirectory: true)
        let grant = FolderAccessGrant(url: url, bookmarkData: Data([1]))
        let bookmarkStore = InMemoryBookmarkStore(grants: [grant])
        let folderAccessService = StubFolderAccessService(
            result: .cancelled,
            resolvedAccesses: [
                grant.id: ResolvedFolderAccess(url: url, isStale: true, didStartAccessing: true)
            ]
        )

        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: bookmarkStore,
            folderAccessService: folderAccessService
        )

        XCTAssertEqual(folderAccessService.resolvedGrantIDs, [grant.id])
        XCTAssertEqual(store.grantedFolderSummaries.map(\.availability), [.available])
        XCTAssertEqual(store.grantedFolderSummaries.map(\.isStale), [true])
        XCTAssertEqual(bookmarkStore.grants.first?.lastResolvedAt != nil, true)
    }

    func testSandboxedInitMarksUnresolvablePersistedGrantsUnavailable() {
        let url = URL(fileURLWithPath: "/tmp/missing-grant", isDirectory: true)
        let grant = FolderAccessGrant(url: url, bookmarkData: Data([1]))
        let folderAccessService = StubFolderAccessService(
            result: .cancelled,
            resolveErrors: [grant.id: ExplorerError.permissionDenied(url.path)]
        )

        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: InMemoryBookmarkStore(grants: [grant]),
            folderAccessService: folderAccessService
        )

        XCTAssertEqual(folderAccessService.resolvedGrantIDs, [grant.id])
        XCTAssertEqual(store.grantedFolderSummaries.map(\.availability), [.unavailable])
        XCTAssertEqual(store.grantedFolderSummaries.map(\.isStale), [false])
    }

    func testChoosingExistingGrantedFolderStopsSupersededAccess() async {
        let url = URL(fileURLWithPath: "/tmp/regranted-folder", isDirectory: true)
        let oldGrant = FolderAccessGrant(url: url, bookmarkData: Data([1]))
        let newGrant = FolderAccessGrant(url: url, bookmarkData: Data([2]))
        let oldAccess = ResolvedFolderAccess(url: url, isStale: false, didStartAccessing: true)
        let newAccess = ResolvedFolderAccess(url: url, isStale: false, didStartAccessing: true)
        let folderAccessService = StubFolderAccessService(
            result: .granted(newGrant, newAccess),
            resolvedAccesses: [oldGrant.id: oldAccess]
        )
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: InMemoryBookmarkStore(grants: [oldGrant]),
            folderAccessService: folderAccessService
        )

        await store.chooseFolderForAccess(startingAt: url)

        XCTAssertEqual(folderAccessService.stoppedAccesses, [oldAccess])
        XCTAssertEqual(store.grantedFolderSummaries.map(\.id), [newGrant.id])
    }

    func testRemoveAndResetGrantedFoldersUpdateSummaries() async {
        let firstURL = URL(fileURLWithPath: "/tmp/granted-one", isDirectory: true)
        let secondURL = URL(fileURLWithPath: "/tmp/granted-two", isDirectory: true)
        let firstGrant = FolderAccessGrant(url: firstURL, bookmarkData: Data([1]))
        let secondGrant = FolderAccessGrant(url: secondURL, bookmarkData: Data([2]))
        let bookmarkStore = InMemoryBookmarkStore(grants: [firstGrant, secondGrant])
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: bookmarkStore,
            folderAccessService: StubFolderAccessService(result: .cancelled)
        )

        await store.removeGrantedFolder(id: firstGrant.id)

        XCTAssertEqual(store.grantedFolderSummaries.map(\.displayPath), [secondURL.standardizedFileURL.path])

        await store.resetGrantedFolders()

        XCTAssertEqual(store.grantedFolderSummaries, [])
    }

    func testChooseFolderCanRetryCapturedPermissionPathAfterAlertClearsPendingPath() async {
        let deniedURL = URL(fileURLWithPath: "/tmp/denied-after-alert", isDirectory: true)
        let grant = FolderAccessGrant(url: deniedURL, bookmarkData: Data([1]))
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            fileSystemService: RetryingPermissionFileSystemService(deniedURL: deniedURL),
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: InMemoryBookmarkStore(),
            folderAccessService: StubFolderAccessService(
                result: .granted(grant, ResolvedFolderAccess(url: deniedURL, isStale: false, didStartAccessing: true))
            )
        )

        await store.navigate(to: deniedURL)
        store.clearError()

        await store.chooseFolderForAccess(
            startingAt: deniedURL,
            retryingPermissionPath: deniedURL.standardizedFileURL.path
        )

        XCTAssertEqual(store.activePane.location.fileSystemURL, deniedURL.standardizedFileURL)
        XCTAssertNil(store.visibleError)
        XCTAssertNil(store.pendingPermissionRecoveryPath)
    }
}

private struct DenyingFileSystemService: FileSystemServicing {
    var deniedURL: URL

    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry] {
        if url.standardizedFileURL == deniedURL.standardizedFileURL {
            throw ExplorerError.permissionDenied(url.path)
        }
        return []
    }
}

private final class RetryingPermissionFileSystemService: FileSystemServicing, @unchecked Sendable {
    private let deniedURL: URL
    private var shouldDeny = true

    init(deniedURL: URL) {
        self.deniedURL = deniedURL.standardizedFileURL
    }

    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry] {
        guard url.standardizedFileURL == deniedURL else {
            return []
        }
        if shouldDeny {
            shouldDeny = false
            throw ExplorerError.permissionDenied(url.path)
        }
        return []
    }
}

private final class InMemoryBookmarkStore: SecurityScopedBookmarkStoring {
    var grants: [FolderAccessGrant] = []

    init(grants: [FolderAccessGrant] = []) {
        self.grants = grants
    }

    func load() -> [FolderAccessGrant] {
        grants
    }

    func save(_ grant: FolderAccessGrant) throws {
        grants.removeAll { $0.url == grant.url || $0.id == grant.id }
        grants.append(grant)
    }

    func remove(id: FolderAccessGrantID) {
        grants.removeAll { $0.id == id }
    }

    func reset() {
        grants.removeAll()
    }
}

private final class StubFolderAccessService: UserSelectedFolderAccessing, @unchecked Sendable {
    var result: FolderAccessSelectionResult
    var resolvedAccesses: [FolderAccessGrantID: ResolvedFolderAccess]
    var resolveErrors: [FolderAccessGrantID: Error]
    var resolvedGrantIDs: [FolderAccessGrantID] = []
    var stoppedAccesses: [ResolvedFolderAccess] = []

    init(
        result: FolderAccessSelectionResult,
        resolvedAccesses: [FolderAccessGrantID: ResolvedFolderAccess] = [:],
        resolveErrors: [FolderAccessGrantID: Error] = [:]
    ) {
        self.result = result
        self.resolvedAccesses = resolvedAccesses
        self.resolveErrors = resolveErrors
    }

    func chooseFolder(startingAt url: URL?, sandboxed: Bool) async throws -> FolderAccessSelectionResult {
        result
    }

    func resolve(_ grant: FolderAccessGrant) throws -> ResolvedFolderAccess {
        resolvedGrantIDs.append(grant.id)
        if let error = resolveErrors[grant.id] {
            throw error
        }
        return resolvedAccesses[grant.id]
            ?? ResolvedFolderAccess(url: grant.url, isStale: false, didStartAccessing: false)
    }

    func stopAccessing(_ access: ResolvedFolderAccess) {
        stoppedAccesses.append(access)
    }
}
