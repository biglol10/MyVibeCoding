import Foundation
import XCTest
@testable import PaneHarbor

@MainActor
final class SidebarShortcutTests: XCTestCase {
    func testChoosingAlreadyGrantedWorkingFolderStillNavigatesToIt() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let chosen = root.appendingPathComponent("chosen", isDirectory: true)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: false)
        let grant = FolderAccessGrant(url: chosen, bookmarkData: Data([1]))
        let access = ShortcutAccess(result: .granted(grant, ResolvedFolderAccess(url: chosen, isStale: false, didStartAccessing: true)))
        let store = makeStore(root: root, access: access, bookmarks: ShortcutBookmarks(grants: [grant]))
        await store.loadInitialDirectory()
        await store.chooseWorkingFolder()
        XCTAssertEqual(store.activePane.currentURL.path, chosen.path)
        XCTAssertEqual(store.pathInput, chosen.path)
    }

    func testFirstWorkingFolderChoiceNavigatesAndCancelKeepsLocation() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let grant = FolderAccessGrant(url: root, bookmarkData: Data([1]))
        let access = ShortcutAccess(result: .granted(grant, ResolvedFolderAccess(url: root, isStale: false, didStartAccessing: true)))
        let store = makeStore(root: root, access: access, bookmarks: ShortcutBookmarks())
        await store.chooseWorkingFolder()
        XCTAssertFalse(store.requiresWorkingFolder)
        XCTAssertEqual(store.activePane.currentURL.path, root.path)
        let cancelled = makeStore(root: root, access: ShortcutAccess(result: .cancelled), bookmarks: ShortcutBookmarks())
        await cancelled.chooseWorkingFolder()
        XCTAssertTrue(cancelled.requiresWorkingFolder)
        XCTAssertEqual(cancelled.activePane.currentURL.path, root.path)
    }
    func testContainerMigrationKeepsFavoriteIDsOrderAndCustomDestinations() {
        let container = URL(fileURLWithPath: "/sandbox-container", isDirectory: true)
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        var old = SidebarState(favorites: SidebarState.defaultFavorites(homeDirectory: container))
        let custom = SidebarFavorite(title: "My project", url: container.appendingPathComponent("custom"))
        old.favorites.insert(custom, at: 1)
        let repaired = SidebarState.repairContainerDefaults(old, sandboxed: true, containerHome: container, userHome: home)
        XCTAssertEqual(repaired.favorites.map(\.id), old.favorites.map(\.id))
        XCTAssertEqual(repaired.favorites.map(\.title), old.favorites.map(\.title))
        XCTAssertEqual(repaired.favorites[0].url.path, home.path)
        XCTAssertEqual(repaired.favorites[1], custom)
        XCTAssertEqual(repaired.favorites[2].url.path, home.appendingPathComponent("Desktop").path)
        XCTAssertEqual(repaired.favorites.last?.url.path, "/Applications")
        XCTAssertEqual(SidebarState.repairContainerDefaults(old, sandboxed: false, containerHome: container, userHome: home), old)
    }

    func testUserHomeMatchesSystemUserOutsideSandbox() {
        XCTAssertEqual(SidebarUserLocations.homeDirectory.path, FileManager.default.homeDirectoryForCurrentUser.path)
        XCTAssertEqual(SidebarState.defaultFavorites().first?.url.path, SidebarUserLocations.homeDirectory.path)
    }

    func testCancelShortcutAccessKeepsPreviousFolderAndDoesNotSaveGrant() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let access = ShortcutAccess(result: .cancelled)
        let bookmarks = ShortcutBookmarks()
        let store = makeStore(root: root, access: access, bookmarks: bookmarks)
        let target = root.appendingPathComponent("target", isDirectory: true)
        await store.navigateFromSidebar(to: target)
        XCTAssertEqual(access.starts.map { $0?.path }, [target.path])
        XCTAssertEqual(store.activePane.currentURL.path, root.path)
        XCTAssertNil(store.visibleError)
        XCTAssertTrue(bookmarks.grants.isEmpty)
        XCTAssertTrue(store.requiresWorkingFolder)
        XCTAssertFalse(store.canAddActiveFolderToFavorites)
    }

    func testShortcutOpensTheFolderActuallyChosenByUser() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let chosen = root.appendingPathComponent("chosen", isDirectory: true)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: false)
        let grant = FolderAccessGrant(url: chosen, bookmarkData: Data([1]))
        let access = ShortcutAccess(result: .granted(grant, ResolvedFolderAccess(url: chosen, isStale: false, didStartAccessing: true)))
        let bookmarks = ShortcutBookmarks()
        let store = makeStore(root: root, access: access, bookmarks: bookmarks)
        await store.navigateFromSidebar(to: root.appendingPathComponent("requested"))
        XCTAssertEqual(store.activePane.currentURL.path, chosen.path)
        XCTAssertFalse(store.requiresWorkingFolder)
        XCTAssertEqual(bookmarks.grants.map(\.id), [grant.id])
        XCTAssertNil(store.visibleError)
    }

    func testAlreadyGrantedShortcutNavigatesWithoutAnotherPicker() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let grant = FolderAccessGrant(url: root, bookmarkData: Data([1]))
        let access = ShortcutAccess(result: .cancelled)
        let store = makeStore(root: root, access: access, bookmarks: ShortcutBookmarks(grants: [grant]))
        await store.loadInitialDirectory()
        await store.navigateFromSidebar(to: child)
        XCTAssertTrue(access.starts.isEmpty)
        XCTAssertEqual(store.activePane.currentURL.path, child.path)
    }

    func testCancellingRecentFolderAccessDoesNotRemoveRecentEntry() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let recent = SidebarRecentFolder(url: root.appendingPathComponent("recent"))
        let suite = "Shortcut-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let sidebar = UserDefaultsSidebarFavoritesStore(defaults: defaults)
        try sidebar.save(SidebarState(favorites: [], recentFolders: [recent]))
        let access = ShortcutAccess(result: .cancelled)
        let store = ExplorerStore(initialURL: root, settingsStore: ShortcutSettings(), sidebarFavoritesStore: sidebar, directoryWatcher: nil,
                                  sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
                                  bookmarkStore: ShortcutBookmarks(), folderAccessService: access)
        await store.navigateToRecentFolder(recent)
        XCTAssertEqual(store.recentFolders, [recent])
        XCTAssertEqual(access.starts.map { $0?.path }, [recent.url.path])
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Sidebar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func makeStore(root: URL, access: ShortcutAccess, bookmarks: ShortcutBookmarks) -> ExplorerStore {
        ExplorerStore(initialURL: root, settingsStore: ShortcutSettings(), sidebarFavoritesStore: ShortcutSidebar(), directoryWatcher: nil, sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
                      bookmarkStore: bookmarks, folderAccessService: access)
    }
}

private final class ShortcutSettings: ExplorerSettingsStoring {
    var value = ExplorerSettings()
    func load() -> ExplorerSettings { value }
    func save(_ settings: ExplorerSettings) { value = settings }
}

private final class ShortcutSidebar: SidebarFavoritesStoring {
    var state = SidebarState(favorites: [], recentFolders: [])
    func load() throws -> SidebarState { state }
    func save(_ state: SidebarState) throws { self.state = state }
    func reset() throws { state = SidebarState(favorites: [], recentFolders: []) }
}

private final class ShortcutBookmarks: SecurityScopedBookmarkStoring {
    var grants: [FolderAccessGrant]
    init(grants: [FolderAccessGrant] = []) { self.grants = grants }
    func load() throws -> [FolderAccessGrant] { grants }
    func save(_ grant: FolderAccessGrant) throws { grants.removeAll { $0.id == grant.id || $0.url == grant.url }; grants.append(grant) }
    func remove(id: FolderAccessGrantID) throws { grants.removeAll { $0.id == id } }
    func reset() { grants = [] }
}

private final class ShortcutAccess: UserSelectedFolderAccessing, @unchecked Sendable {
    let result: FolderAccessSelectionResult
    var starts: [URL?] = []
    init(result: FolderAccessSelectionResult) { self.result = result }
    func chooseFolder(startingAt url: URL?, sandboxed: Bool) async throws -> FolderAccessSelectionResult { starts.append(url); return result }
    func resolve(_ grant: FolderAccessGrant) throws -> ResolvedFolderAccess {
        ResolvedFolderAccess(url: grant.url, isStale: false, didStartAccessing: true)
    }
    func stopAccessing(_ access: ResolvedFolderAccess) {}
}
