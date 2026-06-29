import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
final class ExplorerSidebarStoreTests: XCTestCase {
    func testAddSelectedFolderToFavoritesPersistsAndAvoidsDuplicates() async throws {
        let root = try makeFixture()
        let selected = root.appendingPathComponent("Selected", isDirectory: true)
        let sidebarStore = InMemorySidebarFavoritesStore(state: SidebarState(favorites: [], recentFolders: []))
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: sidebarStore,
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )
        await store.loadInitialDirectory()
        store.updateSelection([selected])

        await store.addSelectedFolderToFavorites()
        await store.addSelectedFolderToFavorites()

        XCTAssertEqual(store.favoriteSidebarItems.map(\.favorite.url), [selected.standardizedFileURL])
        XCTAssertEqual(sidebarStore.savedStates.last?.favorites.map(\.url), [selected.standardizedFileURL])
    }

    func testAddSelectedFolderIgnoresFilesAndMultipleSelection() async throws {
        let root = try makeFixture()
        let file = root.appendingPathComponent("file.txt")
        let selected = root.appendingPathComponent("Selected", isDirectory: true)
        let sidebarStore = InMemorySidebarFavoritesStore(state: SidebarState(favorites: [], recentFolders: []))
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: sidebarStore,
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )
        await store.loadInitialDirectory()

        store.updateSelection([file])
        await store.addSelectedFolderToFavorites()
        store.updateSelection([file, selected])
        await store.addSelectedFolderToFavorites()

        XCTAssertTrue(store.favoriteSidebarItems.isEmpty)
        XCTAssertEqual(sidebarStore.savedStates.last?.favorites, [])
    }

    func testCanAddActiveFolderToFavoritesReflectsActiveFolderDuplicateState() async throws {
        let root = try makeFixture()
        let sidebarStore = InMemorySidebarFavoritesStore(state: SidebarState(favorites: [], recentFolders: []))
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: sidebarStore,
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )

        XCTAssertTrue(store.canAddActiveFolderToFavorites)

        store.addActiveFolderToFavorites()

        XCTAssertFalse(store.canAddActiveFolderToFavorites)
        XCTAssertEqual(store.favoriteSidebarItems.map(\.favorite.url), [root.standardizedFileURL])
        XCTAssertEqual(sidebarStore.savedStates.last?.favorites.map(\.url), [root.standardizedFileURL])
    }

    func testCanAddPrimaryFavoriteUsesSelectedFolderWhenActiveFolderIsAlreadyFavorite() async throws {
        let root = try makeFixture()
        let selected = root.appendingPathComponent("Selected", isDirectory: true)
        let rootFavorite = SidebarFavorite(title: "Root", url: root)
        let sidebarStore = InMemorySidebarFavoritesStore(
            state: SidebarState(favorites: [rootFavorite], recentFolders: [])
        )
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: sidebarStore,
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )
        await store.loadInitialDirectory()
        store.updateSelection([selected])

        XCTAssertTrue(store.canAddPrimaryFolderToFavorites)

        store.addPrimaryFolderToFavorites()

        XCTAssertEqual(store.favoriteSidebarItems.map(\.favorite.url), [
            root.standardizedFileURL,
            selected.standardizedFileURL
        ])
        XCTAssertEqual(sidebarStore.savedStates.last?.favorites.map(\.url), [
            root.standardizedFileURL,
            selected.standardizedFileURL
        ])
    }

    func testPrimaryFavoriteDuplicateSelectionDoesNotAddActiveFolderInstead() async throws {
        let root = try makeFixture()
        let selected = root.appendingPathComponent("Selected", isDirectory: true)
        let selectedFavorite = SidebarFavorite(title: "Selected", url: selected)
        let sidebarStore = InMemorySidebarFavoritesStore(
            state: SidebarState(favorites: [selectedFavorite], recentFolders: [])
        )
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: sidebarStore,
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )
        await store.loadInitialDirectory()
        sidebarStore.savedStates.removeAll()
        store.updateSelection([selected])

        XCTAssertFalse(store.canAddPrimaryFolderToFavorites)

        store.addPrimaryFolderToFavorites()

        XCTAssertEqual(store.favoriteSidebarItems.map(\.favorite.url), [selected.standardizedFileURL])
        XCTAssertNil(sidebarStore.savedStates.last)
    }

    func testRemoveAndReorderFavoritesPersist() async throws {
        let root = try makeFixture()
        let first = SidebarFavorite(title: "First", url: root.appendingPathComponent("Selected", isDirectory: true))
        let second = SidebarFavorite(title: "Second", url: root)
        let sidebarStore = InMemorySidebarFavoritesStore(state: SidebarState(favorites: [first, second], recentFolders: []))
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: sidebarStore,
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )

        store.moveFavorite(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        store.removeFavorite(id: second.id)

        XCTAssertEqual(store.favoriteSidebarItems.map(\.favorite.id), [first.id])
        XCTAssertEqual(sidebarStore.savedStates.last?.favorites.map(\.id), [first.id])
    }

    func testMoveFavoriteUpAndDownPersist() async throws {
        let root = try makeFixture()
        let first = SidebarFavorite(title: "First", url: root.appendingPathComponent("First", isDirectory: true))
        let second = SidebarFavorite(title: "Second", url: root.appendingPathComponent("Second", isDirectory: true))
        let third = SidebarFavorite(title: "Third", url: root.appendingPathComponent("Third", isDirectory: true))
        let sidebarStore = InMemorySidebarFavoritesStore(state: SidebarState(favorites: [first, second, third], recentFolders: []))
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: sidebarStore,
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )

        store.moveFavoriteDown(id: first.id)
        store.moveFavoriteUp(id: third.id)
        store.moveFavoriteUp(id: second.id)
        store.moveFavoriteDown(id: first.id)

        XCTAssertEqual(store.favoriteSidebarItems.map(\.favorite.id), [second.id, third.id, first.id])
        XCTAssertEqual(sidebarStore.savedStates.last?.favorites.map(\.id), [second.id, third.id, first.id])
    }

    func testMoveFavoriteByIDToOffsetPersists() async throws {
        let root = try makeFixture()
        let first = SidebarFavorite(title: "First", url: root.appendingPathComponent("First", isDirectory: true))
        let second = SidebarFavorite(title: "Second", url: root.appendingPathComponent("Second", isDirectory: true))
        let third = SidebarFavorite(title: "Third", url: root.appendingPathComponent("Third", isDirectory: true))
        let sidebarStore = InMemorySidebarFavoritesStore(state: SidebarState(favorites: [first, second, third], recentFolders: []))
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: sidebarStore,
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )

        store.moveFavorite(id: first.id, toOffset: 3)
        store.moveFavorite(id: third.id, toOffset: 0)

        XCTAssertEqual(store.favoriteSidebarItems.map(\.favorite.id), [third.id, second.id, first.id])
        XCTAssertEqual(sidebarStore.savedStates.last?.favorites.map(\.id), [third.id, second.id, first.id])
    }

    func testMissingFavoritePublishesMissingItemWithoutCrashing() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let favorite = SidebarFavorite(title: "Missing", url: missing)
        let store = ExplorerStore(
            initialURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: InMemorySidebarFavoritesStore(state: SidebarState(favorites: [favorite], recentFolders: [])),
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )

        XCTAssertEqual(store.favoriteSidebarItems, [SidebarFavoriteItem(favorite: favorite, isMissing: true)])
    }

    func testSuccessfulFilesystemNavigationRecordsRecentFolders() async throws {
        let root = try makeFixture()
        let selected = root.appendingPathComponent("Selected", isDirectory: true)
        let sidebarStore = InMemorySidebarFavoritesStore(state: SidebarState(favorites: [], recentFolders: []))
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: sidebarStore,
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )
        await store.loadInitialDirectory()

        await store.navigate(to: selected)
        await store.navigate(to: root)

        XCTAssertEqual(store.recentFolders.map(\.url), [root.standardizedFileURL, selected.standardizedFileURL])
        XCTAssertEqual(sidebarStore.savedStates.last?.recentFolders.map(\.url), [root.standardizedFileURL, selected.standardizedFileURL])
    }

    func testSidebarNavigationClearsToolbarFocusAndNavigates() async throws {
        let root = try makeFixture()
        let selected = root.appendingPathComponent("Selected", isDirectory: true)
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: InMemorySidebarFavoritesStore(state: SidebarState(favorites: [], recentFolders: [])),
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )
        await store.loadInitialDirectory()
        store.setToolbarTextInputFocused(true)

        await store.navigateFromSidebar(to: selected)

        XCTAssertEqual(store.requestedFocus, .clear)
        XCTAssertFalse(store.isToolbarTextInputFocused)
        XCTAssertEqual(store.activePane.currentURL, selected.standardizedFileURL)
        XCTAssertEqual(store.pathInput, selected.path)
    }

    func testRecentFolderNavigationClearsToolbarFocusAndNavigates() async throws {
        let root = try makeFixture()
        let selected = root.appendingPathComponent("Selected", isDirectory: true)
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: InMemorySidebarFavoritesStore(state: SidebarState(favorites: [], recentFolders: [])),
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )
        await store.loadInitialDirectory()
        store.setToolbarTextInputFocused(true)

        await store.navigateToRecentFolder(SidebarRecentFolder(url: selected))

        XCTAssertEqual(store.requestedFocus, .clear)
        XCTAssertFalse(store.isToolbarTextInputFocused)
        XCTAssertEqual(store.activePane.currentURL, selected.standardizedFileURL)
        XCTAssertEqual(store.pathInput, selected.path)
    }

    func testMissingRecentFolderClickRemovesItWithoutPresentingError() async throws {
        let root = try makeFixture()
        let missing = root.appendingPathComponent("MissingRecent", isDirectory: true)
        let sidebarStore = InMemorySidebarFavoritesStore(
            state: SidebarState(
                favorites: [],
                recentFolders: [
                    SidebarRecentFolder(url: missing),
                    SidebarRecentFolder(url: root)
                ]
            )
        )
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: sidebarStore,
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )

        await store.navigateToRecentFolder(SidebarRecentFolder(url: missing))

        XCTAssertEqual(store.activePane.currentURL.path, root.path)
        XCTAssertEqual(store.visibleErrorMessage, "")
        XCTAssertEqual(store.recentFolders.map(\.url), [root.standardizedFileURL])
        XCTAssertEqual(sidebarStore.savedStates.last?.recentFolders.map(\.url), [root.standardizedFileURL])
    }

    func testStoredRecentFoldersAreTrimmedToFiveOnLoad() throws {
        let root = try makeFixture()
        let folders = try (0..<7).map { index in
            let folder = root.appendingPathComponent("Recent-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        let expected = Array(folders.prefix(5)).map(\.standardizedFileURL)
        let sidebarStore = InMemorySidebarFavoritesStore(
            state: SidebarState(
                favorites: [],
                recentFolders: folders.map { SidebarRecentFolder(url: $0) }
            )
        )
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: sidebarStore,
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )

        XCTAssertEqual(store.recentFolders.map(\.url), expected)
        XCTAssertEqual(sidebarStore.savedStates.last?.recentFolders.map(\.url), expected)
    }

    func testRecordedRecentFoldersAreLimitedToFive() async throws {
        let root = try makeFixture()
        let folders = try (0..<6).map { index in
            let folder = root.appendingPathComponent("Navigate-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        let sidebarStore = InMemorySidebarFavoritesStore(state: SidebarState(favorites: [], recentFolders: []))
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            sidebarFavoritesStore: sidebarStore,
            directoryWatcher: nil,
            volumeService: StubSidebarVolumeService()
        )
        await store.loadInitialDirectory()

        for folder in folders {
            await store.navigate(to: folder)
        }

        XCTAssertEqual(store.recentFolders.map(\.url), Array(folders.reversed().prefix(5)).map(\.standardizedFileURL))
        XCTAssertEqual(sidebarStore.savedStates.last?.recentFolders.map(\.url), store.recentFolders.map(\.url))
    }

    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExplorerSidebarStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Selected", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("file".utf8).write(to: root.appendingPathComponent("file.txt"))
        return root
    }
}

private final class InMemorySidebarFavoritesStore: SidebarFavoritesStoring {
    private var state: SidebarState
    var savedStates: [SidebarState] = []

    init(state: SidebarState) {
        self.state = state
    }

    func load() -> SidebarState {
        state
    }

    func save(_ state: SidebarState) {
        self.state = state
        savedStates.append(state)
    }
}

private final class InMemoryExplorerSettingsStore: ExplorerSettingsStoring {
    var settings = ExplorerSettings()

    func load() -> ExplorerSettings {
        settings
    }

    func save(_ settings: ExplorerSettings) {
        self.settings = settings
    }
}

private struct StubSidebarVolumeService: VolumeListing {
    func mountedVolumes() async throws -> [MountedVolume] {
        []
    }
}
