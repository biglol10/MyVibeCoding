import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "MyMacFinderSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
    }

    func testDefaultsStoreSavesAndLoadsSettingsAcrossInstances() throws {
        let key = "settings"
        let savedSettings = ExplorerSettings(
            paneMode: .dual,
            isInspectorVisible: false,
            showHiddenFiles: true,
            defaultSort: EntrySortDescriptor(key: .size, direction: .descending, folderFileOrdering: .filesFirst),
            previewByteLimit: .expanded
        )

        try UserDefaultsExplorerSettingsStore(defaults: defaults, key: key).save(savedSettings)
        let loadedSettings = try UserDefaultsExplorerSettingsStore(defaults: defaults, key: key).load()

        XCTAssertEqual(loadedSettings, savedSettings)
    }

    func testDefaultsStoreThrowsAndPreservesStoredBytesWhenDataIsCorrupt() {
        let key = "settings"
        let corruptData = Data("not json".utf8)
        defaults.set(corruptData, forKey: key)

        let store = UserDefaultsExplorerSettingsStore(defaults: defaults, key: key)

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(defaults.data(forKey: key), corruptData)
    }

    func testDefaultsPreviewByteLimitWhenLoadingOlderSettings() throws {
        let key = "settings"
        let oldSettingsJSON = """
        {
          "paneMode": "dual",
          "isInspectorVisible": false,
          "showHiddenFiles": true,
          "defaultSort": {
            "key": "size",
            "direction": "descending",
            "folderFileOrdering": "filesFirst"
          }
        }
        """
        defaults.set(Data(oldSettingsJSON.utf8), forKey: key)

        let loadedSettings = try UserDefaultsExplorerSettingsStore(defaults: defaults, key: key).load()

        XCTAssertEqual(loadedSettings.previewByteLimit, .balanced)
        XCTAssertEqual(loadedSettings.previewMode, .smart)
        XCTAssertTrue(loadedSettings.restorePreviousSession)
    }
}
