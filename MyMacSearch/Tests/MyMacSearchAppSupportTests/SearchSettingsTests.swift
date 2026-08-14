import Foundation
import XCTest
@testable import MyMacSearchAppSupport

final class SearchSettingsTests: XCTestCase {
    func testRecommendedSettingsIncludeOnlyExistingLocalRoots() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(
            at: temporary.appendingPathComponent("Desktop"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: temporary.appendingPathComponent("Developer/Projects"),
            withIntermediateDirectories: true
        )

        let settings = SearchSettings.recommended(homeURL: temporary)

        XCTAssertEqual(
            Set(settings.scopes.map(\.rootPath)),
            [temporary.appendingPathComponent("Desktop").path,
             temporary.appendingPathComponent("Developer/Projects").path]
        )
        XCTAssertFalse(settings.includeHidden)
        XCTAssertFalse(settings.externalVolumesEnabled)
        XCTAssertFalse(settings.networkVolumesEnabled)
        XCTAssertFalse(settings.onboardingConfirmed)
    }

    func testCorruptPrimaryRecoversLastGoodSettings() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = SearchSettingsStore(directoryURL: temporary)
        var first = SearchSettings.recommended(homeURL: temporary)
        first.onboardingConfirmed = true
        try store.save(first)
        var second = first
        second.includeHidden = true
        try store.save(second)
        try Data("not-json".utf8).write(to: store.settingsURL, options: .atomic)

        let recovered = try store.load()

        XCTAssertEqual(recovered, first)
        XCTAssertTrue(store.didRecoverLastGood)
    }

    func testMissingOptionalVolumeIdentityDecodesFromVersionOneSettings() throws {
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "scopes": [{"id":"work","rootPath":"/Volumes/Work","volumeType":"external","isEnabled":true}],
              "excludedPaths": [],
              "includeHidden": false,
              "externalVolumesEnabled": true,
              "networkVolumesEnabled": false,
              "onboardingConfirmed": true,
              "globalShortcut": {"keyCode":49,"modifiers":2048}
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(SearchSettings.self, from: data)

        XCTAssertNil(settings.scopes[0].expectedVolumeUUID)
    }
}
