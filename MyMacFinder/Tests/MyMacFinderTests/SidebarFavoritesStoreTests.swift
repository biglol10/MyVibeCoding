import Foundation
import XCTest
@testable import MyMacFinder

final class SidebarFavoritesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "SidebarFavoritesStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
    }

    func testDefaultsStoreSavesAndLoadsSidebarState() throws {
        let state = SidebarState(
            favorites: [
                SidebarFavorite(title: "Projects", url: URL(fileURLWithPath: "/Users/biglol/Projects", isDirectory: true))
            ],
            recentFolders: [
                SidebarRecentFolder(url: URL(fileURLWithPath: "/Users/biglol/Downloads", isDirectory: true))
            ]
        )

        try UserDefaultsSidebarFavoritesStore(defaults: defaults, key: "sidebar").save(state)
        let loaded = try UserDefaultsSidebarFavoritesStore(defaults: defaults, key: "sidebar").load()

        XCTAssertEqual(loaded, state)
    }

    func testDefaultsStoreSeedsDefaultFavoritesWhenMissing() throws {
        let loaded = try UserDefaultsSidebarFavoritesStore(defaults: defaults, key: "sidebar").load()

        XCTAssertEqual(loaded.favorites.map(\.title), ["Home", "Desktop", "Documents", "Downloads", "Applications"])
        XCTAssertTrue(loaded.recentFolders.isEmpty)
    }

    func testDefaultsStoreThrowsAndPreservesStoredBytesWhenDataIsCorrupt() {
        let corruptData = Data("not json".utf8)
        defaults.set(corruptData, forKey: "sidebar")

        let store = UserDefaultsSidebarFavoritesStore(defaults: defaults, key: "sidebar")

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(defaults.data(forKey: "sidebar"), corruptData)
    }
}
