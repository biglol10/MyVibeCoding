import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
final class ExplorerPersistenceRecoveryTests: XCTestCase {
    func testSettingsLoadFailureUsesDefaultsAndBlocksAutomaticOverwrite() {
        let settingsStore = ControlledSettingsStore(loadError: InjectedPersistenceError.load)
        let store = makeStore(settingsStore: settingsStore)

        XCTAssertNotNil(store.settingsPersistenceErrorMessage)
        XCTAssertEqual(store.paneMode, .single)

        store.isInspectorVisible = false

        XCTAssertEqual(settingsStore.saveCallCount, 0)
    }

    func testSidebarLoadFailureBlocksAutomaticOverwrite() {
        let sidebarStore = ControlledSidebarStore(loadError: InjectedPersistenceError.load)
        let store = makeStore(sidebarStore: sidebarStore)

        XCTAssertNotNil(store.sidebarPersistenceErrorMessage)

        store.addPrimaryFolderToFavorites()

        XCTAssertEqual(sidebarStore.saveCallCount, 0)
    }

    func testSettingsSaveFailureBlocksLaterAutomaticRetries() {
        let settingsStore = ControlledSettingsStore(saveError: InjectedPersistenceError.save)
        let store = makeStore(settingsStore: settingsStore)

        store.isInspectorVisible = false
        store.isInspectorVisible = true

        XCTAssertEqual(settingsStore.saveCallCount, 1)
        XCTAssertNotNil(store.settingsPersistenceErrorMessage)
    }

    func testSuccessfulSettingsResetClearsBlockAndPersistsLiveSettings() {
        let settingsStore = ControlledSettingsStore(loadError: InjectedPersistenceError.load)
        let store = makeStore(settingsStore: settingsStore)
        store.isInspectorVisible = false

        settingsStore.loadError = nil
        store.resetSavedSettings()

        XCTAssertEqual(settingsStore.resetCallCount, 1)
        XCTAssertEqual(settingsStore.saveCallCount, 1)
        XCTAssertEqual(settingsStore.savedSettings.last?.isInspectorVisible, false)
        XCTAssertNil(store.settingsPersistenceErrorMessage)
    }

    func testFailedSettingsResetKeepsBlockAndWarning() {
        let settingsStore = ControlledSettingsStore(
            loadError: InjectedPersistenceError.load,
            resetError: InjectedPersistenceError.reset
        )
        let store = makeStore(settingsStore: settingsStore)

        store.resetSavedSettings()
        store.isInspectorVisible = false

        XCTAssertEqual(settingsStore.resetCallCount, 1)
        XCTAssertEqual(settingsStore.saveCallCount, 0)
        XCTAssertNotNil(store.settingsPersistenceErrorMessage)
    }

    func testSuccessfulSidebarResetRestoresDefaultFavoritesAndClearsBlock() {
        let sidebarStore = ControlledSidebarStore(loadError: InjectedPersistenceError.load)
        let store = makeStore(sidebarStore: sidebarStore)

        sidebarStore.loadError = nil
        store.resetSavedSidebar()

        XCTAssertEqual(sidebarStore.resetCallCount, 1)
        XCTAssertEqual(sidebarStore.saveCallCount, 1)
        XCTAssertEqual(
            store.favoriteSidebarItems.map(\.favorite.title),
            ["Home", "Desktop", "Documents", "Downloads", "Applications"]
        )
        XCTAssertNil(store.sidebarPersistenceErrorMessage)
    }

    func testSessionLoadFailureIsReportedAndExplicitResetClearsIt() {
        let sessionStore = ControlledSessionStore(loadError: InjectedPersistenceError.load)
        let store = makeStore(sessionStore: sessionStore)

        XCTAssertNotNil(store.sessionPersistenceErrorMessage)

        sessionStore.loadError = nil
        store.resetSavedSession()

        XCTAssertEqual(sessionStore.resetCallCount, 1)
        XCTAssertEqual(sessionStore.saveCallCount, 1)
        XCTAssertNotNil(sessionStore.snapshot)
        XCTAssertNil(store.sessionPersistenceErrorMessage)
    }

    private func makeStore(
        settingsStore: ControlledSettingsStore = ControlledSettingsStore(),
        sidebarStore: ControlledSidebarStore = ControlledSidebarStore(),
        sessionStore: ControlledSessionStore = ControlledSessionStore()
    ) -> ExplorerStore {
        ExplorerStore(
            initialURL: URL(fileURLWithPath: "/tmp/MyMacFinderPersistenceRecovery", isDirectory: true),
            settingsStore: settingsStore,
            sidebarFavoritesStore: sidebarStore,
            sessionStore: sessionStore,
            directoryWatcher: nil
        )
    }
}

private enum InjectedPersistenceError: LocalizedError {
    case load
    case save
    case reset

    var errorDescription: String? {
        switch self {
        case .load: return "Injected load failure"
        case .save: return "Injected save failure"
        case .reset: return "Injected reset failure"
        }
    }
}

private final class ControlledSettingsStore: ExplorerSettingsStoring {
    var settings: ExplorerSettings
    var loadError: Error?
    var saveError: Error?
    var resetError: Error?
    private(set) var savedSettings: [ExplorerSettings] = []
    private(set) var saveCallCount = 0
    private(set) var resetCallCount = 0

    init(
        settings: ExplorerSettings = ExplorerSettings(),
        loadError: Error? = nil,
        saveError: Error? = nil,
        resetError: Error? = nil
    ) {
        self.settings = settings
        self.loadError = loadError
        self.saveError = saveError
        self.resetError = resetError
    }

    func load() throws -> ExplorerSettings {
        if let loadError { throw loadError }
        return settings
    }

    func save(_ settings: ExplorerSettings) throws {
        saveCallCount += 1
        if let saveError { throw saveError }
        self.settings = settings
        savedSettings.append(settings)
    }

    func reset() throws {
        resetCallCount += 1
        if let resetError { throw resetError }
    }
}

private final class ControlledSidebarStore: SidebarFavoritesStoring {
    var state: SidebarState
    var loadError: Error?
    var saveError: Error?
    var resetError: Error?
    private(set) var saveCallCount = 0
    private(set) var resetCallCount = 0

    init(
        state: SidebarState = SidebarState(favorites: [], recentFolders: []),
        loadError: Error? = nil,
        saveError: Error? = nil,
        resetError: Error? = nil
    ) {
        self.state = state
        self.loadError = loadError
        self.saveError = saveError
        self.resetError = resetError
    }

    func load() throws -> SidebarState {
        if let loadError { throw loadError }
        return state
    }

    func save(_ state: SidebarState) throws {
        saveCallCount += 1
        if let saveError { throw saveError }
        self.state = state
    }

    func reset() throws {
        resetCallCount += 1
        if let resetError { throw resetError }
    }
}

private final class ControlledSessionStore: ExplorerSessionStoring {
    var snapshot: ExplorerSessionSnapshot?
    var loadError: Error?
    var saveError: Error?
    var resetError: Error?
    private(set) var saveCallCount = 0
    private(set) var resetCallCount = 0

    init(
        snapshot: ExplorerSessionSnapshot? = nil,
        loadError: Error? = nil,
        saveError: Error? = nil,
        resetError: Error? = nil
    ) {
        self.snapshot = snapshot
        self.loadError = loadError
        self.saveError = saveError
        self.resetError = resetError
    }

    func load() throws -> ExplorerSessionSnapshot? {
        if let loadError { throw loadError }
        return snapshot
    }

    func save(_ snapshot: ExplorerSessionSnapshot) throws {
        saveCallCount += 1
        if let saveError { throw saveError }
        self.snapshot = snapshot
    }

    func reset() throws {
        resetCallCount += 1
        if let resetError { throw resetError }
        snapshot = nil
    }
}
