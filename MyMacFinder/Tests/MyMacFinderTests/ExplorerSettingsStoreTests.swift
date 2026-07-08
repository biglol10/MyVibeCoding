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

    func testDefaultsStoreSavesAndLoadsSettingsAcrossInstances() {
        let key = "settings"
        let savedSettings = ExplorerSettings(
            paneMode: .dual,
            isInspectorVisible: false,
            showHiddenFiles: true,
            defaultSort: EntrySortDescriptor(key: .size, direction: .descending, folderFileOrdering: .filesFirst),
            previewByteLimit: .expanded
        )

        UserDefaultsExplorerSettingsStore(defaults: defaults, key: key).save(savedSettings)
        let loadedSettings = UserDefaultsExplorerSettingsStore(defaults: defaults, key: key).load()

        XCTAssertEqual(loadedSettings, savedSettings)
    }

    func testDefaultsStoreFallsBackToDefaultsWhenDataIsCorrupt() {
        let key = "settings"
        defaults.set(Data("not json".utf8), forKey: key)

        let loadedSettings = UserDefaultsExplorerSettingsStore(defaults: defaults, key: key).load()

        XCTAssertEqual(loadedSettings, ExplorerSettings())
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

        let loadedSettings = UserDefaultsExplorerSettingsStore(defaults: defaults, key: key).load()

        XCTAssertEqual(loadedSettings.previewByteLimit, .balanced)
        XCTAssertEqual(loadedSettings.previewMode, .smart)
    }
}
