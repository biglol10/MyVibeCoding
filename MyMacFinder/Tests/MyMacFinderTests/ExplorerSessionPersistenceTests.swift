import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
final class ExplorerSessionPersistenceTests: XCTestCase {
    func testRapidWorkspaceChangesCoalesceIntoOneLatestSnapshot() async {
        let sessionStore = RecordingSessionStore()
        let store = makeStore(sessionStore: sessionStore, debounceNanoseconds: 1_000_000)

        store.sortActivePane(by: .size)
        store.sortActivePane(by: .dateModified)
        await store.waitForPendingSessionPersistence()

        XCTAssertEqual(sessionStore.saveCallCount, 1)
        XCTAssertEqual(sessionStore.snapshots.last?.tabs[0].panes[0].sort.key, .dateModified)
    }

    func testTransientSearchChangesDoNotPersistSession() async {
        let initialURL = URL(fileURLWithPath: "/tmp/MyMacFinderSessionPersistence", isDirectory: true)
        let existing = ExplorerSessionSnapshot(
            tabs: [
                ExplorerSessionTab(
                    panes: [
                        ExplorerSessionPane(
                            location: .fileSystem(initialURL),
                            sort: EntrySortDescriptor(),
                            group: nil
                        )
                    ],
                    activePaneIndex: 0
                )
            ],
            activeTabIndex: 0
        )
        let sessionStore = RecordingSessionStore(snapshot: existing)
        let store = makeStore(sessionStore: sessionStore, debounceNanoseconds: 0)

        store.setSearchQuery("temporary")
        await store.waitForPendingSessionPersistence()

        XCTAssertEqual(sessionStore.saveCallCount, 0)
    }

    func testDisabledRestorationDoesNotOverwriteExistingSnapshot() async {
        let existing = ExplorerSessionSnapshot(
            tabs: [
                ExplorerSessionTab(
                    panes: [
                        ExplorerSessionPane(
                            location: .fileSystem(URL(fileURLWithPath: "/tmp/kept", isDirectory: true)),
                            sort: EntrySortDescriptor(),
                            group: nil
                        )
                    ],
                    activePaneIndex: 0
                )
            ],
            activeTabIndex: 0
        )
        let sessionStore = RecordingSessionStore(snapshot: existing)
        let store = makeStore(
            settings: ExplorerSettings(restorePreviousSession: false),
            sessionStore: sessionStore,
            debounceNanoseconds: 0
        )

        store.sortActivePane(by: .size)
        await store.flushSessionPersistence()

        XCTAssertEqual(sessionStore.saveCallCount, 0)
        XCTAssertEqual(sessionStore.snapshot, existing)
    }

    func testFlushCancelsDebounceAndWritesCurrentSnapshotImmediately() async {
        let sessionStore = RecordingSessionStore()
        let store = makeStore(sessionStore: sessionStore, debounceNanoseconds: 5_000_000_000)

        store.sortActivePane(by: .kind)
        await store.flushSessionPersistence()

        XCTAssertEqual(sessionStore.saveCallCount, 1)
        XCTAssertEqual(sessionStore.snapshots.last?.tabs[0].panes[0].sort.key, .kind)
    }

    func testSessionSaveFailureBlocksLaterAutomaticWrites() async {
        let sessionStore = RecordingSessionStore(saveError: PersistenceSaveFailure.injected)
        let store = makeStore(sessionStore: sessionStore, debounceNanoseconds: 0)

        store.sortActivePane(by: .size)
        await store.waitForPendingSessionPersistence()
        store.sortActivePane(by: .kind)
        await store.flushSessionPersistence()

        XCTAssertEqual(sessionStore.saveCallCount, 1)
        XCTAssertNotNil(store.sessionPersistenceErrorMessage)
    }

    private func makeStore(
        settings: ExplorerSettings = ExplorerSettings(restorePreviousSession: true),
        sessionStore: RecordingSessionStore,
        debounceNanoseconds: UInt64
    ) -> ExplorerStore {
        ExplorerStore(
            initialURL: URL(fileURLWithPath: "/tmp/MyMacFinderSessionPersistence", isDirectory: true),
            settingsStore: SessionPersistenceSettingsStore(settings: settings),
            sidebarFavoritesStore: SessionPersistenceSidebarStore(),
            sessionStore: sessionStore,
            directoryWatcher: nil,
            sessionPersistenceDebounceNanoseconds: debounceNanoseconds
        )
    }
}

private enum PersistenceSaveFailure: Error {
    case injected
}

private final class RecordingSessionStore: ExplorerSessionStoring {
    var snapshot: ExplorerSessionSnapshot?
    var saveError: Error?
    private(set) var snapshots: [ExplorerSessionSnapshot] = []
    private(set) var saveCallCount = 0

    init(snapshot: ExplorerSessionSnapshot? = nil, saveError: Error? = nil) {
        self.snapshot = snapshot
        self.saveError = saveError
    }

    func load() -> ExplorerSessionSnapshot? { snapshot }

    func save(_ snapshot: ExplorerSessionSnapshot) throws {
        saveCallCount += 1
        if let saveError { throw saveError }
        self.snapshot = snapshot
        snapshots.append(snapshot)
    }

    func reset() { snapshot = nil }
}

private final class SessionPersistenceSettingsStore: ExplorerSettingsStoring {
    var settings: ExplorerSettings

    init(settings: ExplorerSettings) {
        self.settings = settings
    }

    func load() -> ExplorerSettings { settings }
    func save(_ settings: ExplorerSettings) { self.settings = settings }
}

private final class SessionPersistenceSidebarStore: SidebarFavoritesStoring {
    func load() -> SidebarState { SidebarState(favorites: [], recentFolders: []) }
    func save(_ state: SidebarState) {}
}
