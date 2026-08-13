import XCTest
@testable import MyMacCleanCore

final class AppDiscoveryServiceTests: XCTestCase {
    func testDiscoversOnlyAppBundlesFromConfiguredRoots() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "discovery")
        _ = try TestFixtures.makeAppBundle(root: root, name: "Figma", bundleIdentifier: "com.figma.Desktop")
        _ = try TestFixtures.makeAppBundle(root: root, name: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap")
        try "not an app".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let apps = try await AppDiscoveryService(searchRoots: [root]).discoverApps()

        XCTAssertEqual(apps.map(\.displayName).sorted(), ["Figma", "Slack"])
    }

    func testDiscoversNestedAppsButSkipsEmbeddedHelpers() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "nested-discovery")
        let nested = root.appendingPathComponent("Vendor", isDirectory: true)
        let app = try TestFixtures.makeAppBundle(
            root: nested,
            name: "Editor",
            bundleIdentifier: "com.example.Editor"
        )
        _ = try TestFixtures.makeAppBundle(
            root: app.appendingPathComponent("Contents/Library/LoginItems", isDirectory: true),
            name: "Editor Helper",
            bundleIdentifier: "com.example.Editor.Helper"
        )

        let result = await AppDiscoveryService(searchRoots: [root]).discoverAppsWithCoverage()

        XCTAssertEqual(result.value.map(\.displayName), ["Editor"])
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testReportsInvalidAppsWithoutDroppingValidApps() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "discovery-issues")
        _ = try TestFixtures.makeAppBundle(
            root: root,
            name: "Valid",
            bundleIdentifier: "com.example.Valid"
        )
        let broken = root.appendingPathComponent("Broken.app", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)

        let result = await AppDiscoveryService(searchRoots: [root]).discoverAppsWithCoverage()

        XCTAssertEqual(result.value.map(\.displayName), ["Valid"])
        XCTAssertEqual(result.issues.map(\.path), [broken.path])
        XCTAssertFalse(result.issues[0].permissionRelated)
    }

    func testScanIssueClassifiesPermissionErrors() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileReadNoPermission.rawValue
        )

        let issue = ScanIssue.from(path: URL(fileURLWithPath: "/private/example"), error: error)

        XCTAssertTrue(issue.permissionRelated)
    }

    func testReportsExistingSearchRootThatCannotBeEnumerated() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "discovery-invalid-root")
        let file = root.appendingPathComponent("Applications.txt")
        try Data("not a directory".utf8).write(to: file)

        let result = await AppDiscoveryService(searchRoots: [file]).discoverAppsWithCoverage()

        XCTAssertTrue(result.value.isEmpty)
        XCTAssertEqual(result.issues.map(\.path), [file.path])
    }

    func testDeduplicatesAppsFoundThroughResolvedSearchRoots() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "discovery-dedup")
        _ = try TestFixtures.makeAppBundle(
            root: root,
            name: "Editor",
            bundleIdentifier: "com.example.Editor"
        )
        let alias = root.deletingLastPathComponent().appendingPathComponent("discovery-dedup-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: alias) }

        let result = await AppDiscoveryService(searchRoots: [root, alias]).discoverAppsWithCoverage()

        XCTAssertEqual(result.value.map(\.displayName), ["Editor"])
    }
}
