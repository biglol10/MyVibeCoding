import XCTest
@testable import MyMacCleanCore

final class CandidateMatcherTests: XCTestCase {
    func testHighConfidenceForBundleIdentifierPath() {
        let app = InstalledApp(
            displayName: "Figma",
            bundleIdentifier: "com.figma.Desktop",
            version: nil,
            executableName: "Figma",
            bundleURL: URL(fileURLWithPath: "/Applications/Figma.app"),
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )

        let match = CandidateMatcher().match(
            url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.figma.Desktop"),
            app: app,
            kind: .cache
        )

        XCTAssertEqual(match?.confidence, .high)
        XCTAssertEqual(match?.defaultSelected, true)
    }

    func testDoesNotMatchPartialUnrelatedNames() {
        let app = InstalledApp(
            displayName: "Arc",
            bundleIdentifier: "company.thebrowser.Browser",
            version: nil,
            executableName: "Arc",
            bundleURL: URL(fileURLWithPath: "/Applications/Arc.app"),
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )

        let match = CandidateMatcher().match(
            url: URL(fileURLWithPath: "/Users/me/Library/Application Support/Archive Utility"),
            app: app,
            kind: .applicationSupport
        )

        XCTAssertNil(match)
    }

    func testDoesNotMatchFilesThatShareOnlyOneDisplayNameToken() {
        let app = InstalledApp(
            displayName: "MyMacClean Delete Test",
            bundleIdentifier: "com.local.MyMacCleanDeleteTest",
            version: nil,
            executableName: "MyMacClean Delete Test",
            bundleURL: URL(fileURLWithPath: "/Users/me/Applications/MyMacClean Delete Test.app"),
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )

        let preferenceMatch = CandidateMatcher().match(
            url: URL(fileURLWithPath: "/Users/me/Library/Preferences/com.local.mymacclean.plist"),
            app: app,
            kind: .preferences
        )
        let appleCacheMatch = CandidateMatcher().match(
            url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.apple.cache_delete"),
            app: app,
            kind: .cache
        )

        XCTAssertNil(preferenceMatch)
        XCTAssertNil(appleCacheMatch)
    }

    func testMatchesFullDisplayNameFolder() {
        let app = InstalledApp(
            displayName: "MyMacClean Delete Test",
            bundleIdentifier: "com.local.MyMacCleanDeleteTest",
            version: nil,
            executableName: "MyMacClean Delete Test",
            bundleURL: URL(fileURLWithPath: "/Users/me/Applications/MyMacClean Delete Test.app"),
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )

        let match = CandidateMatcher().match(
            url: URL(fileURLWithPath: "/Users/me/Library/Application Support/MyMacClean Delete Test"),
            app: app,
            kind: .applicationSupport
        )

        XCTAssertEqual(match?.confidence, .medium)
        XCTAssertEqual(match?.defaultSelected, true)
    }

    func testBundleIdentifierMatchCarriesStrongEvidence() {
        let app = InstalledApp(
            displayName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            version: nil,
            executableName: "Cursor",
            bundleURL: URL(fileURLWithPath: "/Applications/Cursor.app"),
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )

        let match = CandidateMatcher().match(
            url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.todesktop.230313mzl4w4u92"),
            app: app,
            kind: .cache
        )

        XCTAssertEqual(match?.evidence, [
            MatchEvidence(
                type: .bundleIdentifier,
                matchedValue: "com.todesktop.230313mzl4w4u92",
                sourcePath: "/Users/me/Library/Caches/com.todesktop.230313mzl4w4u92",
                strength: .strong
            )
        ])
    }

    func testFullAppNameMatchCarriesExactNameEvidence() {
        let app = InstalledApp(
            displayName: "MyMacClean Delete Test",
            bundleIdentifier: "com.local.MyMacCleanDeleteTest",
            version: nil,
            executableName: "MyMacClean Delete Test",
            bundleURL: URL(fileURLWithPath: "/Users/me/Applications/MyMacClean Delete Test.app"),
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )

        let match = CandidateMatcher().match(
            url: URL(fileURLWithPath: "/Users/me/Library/Application Support/MyMacClean Delete Test"),
            app: app,
            kind: .applicationSupport
        )

        XCTAssertEqual(match?.evidence.first?.type, .exactAppName)
        XCTAssertEqual(match?.evidence.first?.strength, .medium)
    }
}
