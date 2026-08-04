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

    func testChooseFolderGenericFailureSurfacesAsOperationFailure() async {
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: InMemoryBookmarkStore(),
            folderAccessService: StubFolderAccessService(
                result: .cancelled,
                chooseError: NSError(domain: "bookmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "bookmark save failed"])
            )
        )

        await store.chooseFolderForAccess()

        XCTAssertEqual(store.visibleError, .operationFailed("bookmark save failed"))
    }

    func testRenameFallbackErrorIsOperationFailure() {
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil
        )

        let error = store.fallbackError(
            for: .rename,
            underlying: NSError(domain: "rename", code: 2, userInfo: [NSLocalizedDescriptionKey: "rename failed"])
        )

        XCTAssertEqual(error, .operationFailed("rename failed"))
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

    func testSandboxedInitRefreshesBookmarkDataWhenPersistedGrantIsStale() {
        let url = URL(fileURLWithPath: "/tmp/stale-persisted-grant", isDirectory: true)
        let grant = FolderAccessGrant(url: url, bookmarkData: Data([1]))
        let bookmarkStore = InMemoryBookmarkStore(grants: [grant])
        let refreshedBookmarkData = Data([9, 9, 9])
        let folderAccessService = StubFolderAccessService(
            result: .cancelled,
            resolvedAccesses: [
                grant.id: ResolvedFolderAccess(
                    url: url,
                    isStale: true,
                    didStartAccessing: true,
                    refreshedBookmarkData: refreshedBookmarkData
                )
            ]
        )

        _ = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: bookmarkStore,
            folderAccessService: folderAccessService
        )

        XCTAssertEqual(bookmarkStore.grants.first?.bookmarkData, refreshedBookmarkData)
    }

    func testCorruptedPersistedGrantDataSurfacesErrorWithoutResolvingGrants() {
        let bookmarkStore = InMemoryBookmarkStore(
            loadError: SecurityScopedBookmarkStoreError.corruptedData
        )
        let folderAccessService = StubFolderAccessService(result: .cancelled)

        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: bookmarkStore,
            folderAccessService: folderAccessService
        )

        XCTAssertEqual(store.grantedFolderSummaries, [])
        XCTAssertEqual(folderAccessService.resolvedGrantIDs, [])
        XCTAssertEqual(
            store.folderAccessPersistenceErrorMessage,
            SecurityScopedBookmarkStoreError.corruptedData.localizedDescription
        )
        XCTAssertEqual(
            store.visibleError,
            .operationFailed(SecurityScopedBookmarkStoreError.corruptedData.localizedDescription)
        )
    }

    func testSandboxedInitStopsResolvedAccessWhenRefreshedGrantCannotBeSaved() {
        let url = URL(fileURLWithPath: "/tmp/unsaved-refreshed-grant", isDirectory: true)
        let grant = FolderAccessGrant(url: url, bookmarkData: Data([1]))
        let access = ResolvedFolderAccess(
            url: url,
            isStale: true,
            didStartAccessing: true,
            refreshedBookmarkData: Data([9])
        )
        let bookmarkStore = InMemoryBookmarkStore(
            grants: [grant],
            saveError: BookmarkStoreStubError.saveFailed
        )
        let folderAccessService = StubFolderAccessService(
            result: .cancelled,
            resolvedAccesses: [grant.id: access]
        )

        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: bookmarkStore,
            folderAccessService: folderAccessService
        )

        XCTAssertEqual(folderAccessService.stoppedAccesses, [access])
        XCTAssertEqual(store.grantedFolderSummaries.map(\.availability), [.unavailable])
        XCTAssertEqual(bookmarkStore.grants, [grant])
        XCTAssertEqual(store.folderAccessPersistenceErrorMessage, "bookmark save failed")
        XCTAssertEqual(store.visibleError, .operationFailed("bookmark save failed"))
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

    func testChooseFolderSaveFailureStopsNewAccessWithoutStoppingExistingAccess() async {
        let url = URL(fileURLWithPath: "/tmp/regrant-save-failure", isDirectory: true)
        let oldGrant = FolderAccessGrant(url: url, bookmarkData: Data([1]))
        let newGrant = FolderAccessGrant(url: url, bookmarkData: Data([2]))
        let oldAccess = ResolvedFolderAccess(url: url, isStale: false, didStartAccessing: true)
        let newAccess = ResolvedFolderAccess(url: url, isStale: false, didStartAccessing: true)
        let bookmarkStore = InMemoryBookmarkStore(grants: [oldGrant])
        let folderAccessService = StubFolderAccessService(
            result: .granted(newGrant, newAccess),
            resolvedAccesses: [oldGrant.id: oldAccess]
        )
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: bookmarkStore,
            folderAccessService: folderAccessService
        )
        bookmarkStore.saveError = BookmarkStoreStubError.saveFailed

        await store.chooseFolderForAccess(startingAt: url)

        XCTAssertEqual(folderAccessService.stoppedAccesses, [newAccess])
        XCTAssertEqual(bookmarkStore.grants.map(\.id), [oldGrant.id])
        XCTAssertEqual(store.grantedFolderSummaries.map(\.id), [oldGrant.id])
        XCTAssertEqual(store.grantedFolderSummaries.map(\.availability), [.available])
        XCTAssertEqual(store.visibleError, .operationFailed("bookmark save failed"))
    }

    func testRemoveGrantFailureKeepsActiveAccessAndSummary() async {
        let url = URL(fileURLWithPath: "/tmp/remove-grant-failure", isDirectory: true)
        let grant = FolderAccessGrant(url: url, bookmarkData: Data([1]))
        let access = ResolvedFolderAccess(url: url, isStale: false, didStartAccessing: true)
        let bookmarkStore = InMemoryBookmarkStore(grants: [grant])
        let folderAccessService = StubFolderAccessService(
            result: .cancelled,
            resolvedAccesses: [grant.id: access]
        )
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: bookmarkStore,
            folderAccessService: folderAccessService
        )
        bookmarkStore.removeError = BookmarkStoreStubError.removeFailed

        await store.removeGrantedFolder(id: grant.id)

        XCTAssertEqual(folderAccessService.stoppedAccesses, [])
        XCTAssertEqual(bookmarkStore.grants.map(\.id), [grant.id])
        XCTAssertEqual(store.grantedFolderSummaries.map(\.availability), [.available])
        XCTAssertEqual(store.visibleError, .operationFailed("bookmark remove failed"))
    }

    func testResetGrantedFoldersClearsPersistenceError() async {
        let bookmarkStore = InMemoryBookmarkStore(
            loadError: SecurityScopedBookmarkStoreError.corruptedData
        )
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: bookmarkStore,
            folderAccessService: StubFolderAccessService(result: .cancelled)
        )

        await store.resetGrantedFolders()

        XCTAssertNil(store.folderAccessPersistenceErrorMessage)
        XCTAssertEqual(store.grantedFolderSummaries, [])
        XCTAssertNil(store.visibleError)
        XCTAssertEqual(bookmarkStore.resetCallCount, 1)
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
    var loadError: Error?
    var saveError: Error?
    var removeError: Error?
    var resetCallCount = 0

    init(
        grants: [FolderAccessGrant] = [],
        loadError: Error? = nil,
        saveError: Error? = nil,
        removeError: Error? = nil
    ) {
        self.grants = grants
        self.loadError = loadError
        self.saveError = saveError
        self.removeError = removeError
    }

    func load() throws -> [FolderAccessGrant] {
        if let loadError {
            throw loadError
        }
        return grants
    }

    func save(_ grant: FolderAccessGrant) throws {
        if let saveError {
            throw saveError
        }
        grants.removeAll { $0.url == grant.url || $0.id == grant.id }
        grants.append(grant)
    }

    func remove(id: FolderAccessGrantID) throws {
        if let removeError {
            throw removeError
        }
        grants.removeAll { $0.id == id }
    }

    func reset() {
        resetCallCount += 1
        loadError = nil
        saveError = nil
        removeError = nil
        grants.removeAll()
    }
}

private enum BookmarkStoreStubError: LocalizedError {
    case saveFailed
    case removeFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "bookmark save failed"
        case .removeFailed:
            return "bookmark remove failed"
        }
    }
}

private final class StubFolderAccessService: UserSelectedFolderAccessing, @unchecked Sendable {
    var result: FolderAccessSelectionResult
    var chooseError: Error?
    var resolvedAccesses: [FolderAccessGrantID: ResolvedFolderAccess]
    var resolveErrors: [FolderAccessGrantID: Error]
    var resolvedGrantIDs: [FolderAccessGrantID] = []
    var stoppedAccesses: [ResolvedFolderAccess] = []

    init(
        result: FolderAccessSelectionResult,
        chooseError: Error? = nil,
        resolvedAccesses: [FolderAccessGrantID: ResolvedFolderAccess] = [:],
        resolveErrors: [FolderAccessGrantID: Error] = [:]
    ) {
        self.result = result
        self.chooseError = chooseError
        self.resolvedAccesses = resolvedAccesses
        self.resolveErrors = resolveErrors
    }

    func chooseFolder(startingAt url: URL?, sandboxed: Bool) async throws -> FolderAccessSelectionResult {
        if let chooseError {
            throw chooseError
        }
        return result
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
