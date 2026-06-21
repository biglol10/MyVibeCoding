import XCTest
@testable import MyMacCleanCore

final class OrphanFileScannerTests: XCTestCase {
    func testFindsBundleIdentifierLeftoversForMissingApp() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "orphans-home")
        let cache = home.appendingPathComponent("Library/Caches/com.todesktop.230313mzl4w4u92", isDirectory: true)
        let prefs = home.appendingPathComponent("Library/Preferences/com.todesktop.230313mzl4w4u92.plist")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefs.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4).write(to: prefs)

        let groups = try await OrphanFileScanner(homeDirectory: home, installedApps: []).scan()

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].inferredIdentifier, "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(Set(groups[0].candidates.map(\.url)), [cache, prefs])
    }

    func testDoesNotFlagInstalledAppLeftoversAsOrphans() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "orphans-installed-home")
        let cache = home.appendingPathComponent("Library/Caches/com.figma.Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let app = InstalledApp(
            displayName: "Figma",
            bundleIdentifier: "com.figma.Desktop",
            version: nil,
            executableName: "Figma",
            bundleURL: home.appendingPathComponent("Applications/Figma.app"),
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )

        let groups = try await OrphanFileScanner(homeDirectory: home, installedApps: [app]).scan()

        XCTAssertTrue(groups.isEmpty)
    }

    func testDoesNotTreatGenericCursorNamedDevelopmentPackagesAsCursorOrphans() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "orphans-yarn-home")
        let yarnPackage = home.appendingPathComponent("Library/Caches/Yarn/v6/npm-cli-cursor-3.1.0-integrity", isDirectory: true)
        try FileManager.default.createDirectory(at: yarnPackage, withIntermediateDirectories: true)

        let groups = try await OrphanFileScanner(homeDirectory: home, installedApps: []).scan()

        XCTAssertTrue(groups.isEmpty)
    }

    func testDoesNotFlagAppleOrTeamPrefixedSharedContainersAsOrphans() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "orphans-system-home")
        let applePreference = home.appendingPathComponent("Library/Preferences/com.apple.Accessibility.plist")
        let teamContainer = home.appendingPathComponent("Library/Group Containers/74J34U3R6X.com.apple.iWork", isDirectory: true)
        try FileManager.default.createDirectory(at: applePreference.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: teamContainer, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4).write(to: applePreference)

        let groups = try await OrphanFileScanner(homeDirectory: home, installedApps: []).scan()

        XCTAssertTrue(groups.isEmpty)
    }

    func testDoesNotFlagInstalledAppHelperSuffixAsOrphan() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "orphans-helper-home")
        let helperCache = home.appendingPathComponent("Library/Caches/com.figma.Desktop.ShipIt", isDirectory: true)
        try FileManager.default.createDirectory(at: helperCache, withIntermediateDirectories: true)
        let app = InstalledApp(
            displayName: "Figma",
            bundleIdentifier: "com.figma.Desktop",
            version: nil,
            executableName: "Figma",
            bundleURL: home.appendingPathComponent("Applications/Figma.app"),
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )

        let groups = try await OrphanFileScanner(homeDirectory: home, installedApps: [app]).scan()

        XCTAssertTrue(groups.isEmpty)
    }

    func testDoesNotFlagExplicitlyExcludedBundleIdentifierAsOrphan() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "orphans-excluded-home")
        let ownCache = home.appendingPathComponent("Library/Caches/com.local.mymacclean", isDirectory: true)
        try FileManager.default.createDirectory(at: ownCache, withIntermediateDirectories: true)

        let groups = try await OrphanFileScanner(
            homeDirectory: home,
            installedApps: [],
            excludedBundleIdentifiers: ["com.local.mymacclean"]
        ).scan()

        XCTAssertTrue(groups.isEmpty)
    }

    func testLaunchAgentsRequireManualSelection() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "orphans-launch-agent-home")
        let launchAgent = home.appendingPathComponent("Library/LaunchAgents/ai.openclaw.gateway.plist")
        try FileManager.default.createDirectory(at: launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4).write(to: launchAgent)

        let groups = try await OrphanFileScanner(homeDirectory: home, installedApps: []).scan()

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].candidates[0].safety, .review)
        XCTAssertFalse(groups[0].candidates[0].defaultSelected)
        XCTAssertTrue(groups[0].candidates[0].requiresManualReview)
    }
}
