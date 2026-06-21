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
}
