import XCTest
@testable import MyMacCleanCore

final class StartupItemControllerTests: XCTestCase {
    func testControllerDisablesAndEnablesUserLaunchAgentByRenamingFile() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "startup-controller")
        let userLaunchAgents = root.appendingPathComponent("UserLaunchAgents", isDirectory: true)
        let plistURL = try writeLaunchPlist(
            named: "com.example.agent.plist",
            in: userLaunchAgents,
            values: [
                "Label": "com.example.agent",
                "Program": "/bin/echo"
            ]
        )

        let scanner = StartupItemScanner(
            userLaunchAgentsURL: userLaunchAgents,
            globalLaunchAgentsURL: root.appendingPathComponent("GlobalLaunchAgents", isDirectory: true),
            globalLaunchDaemonsURL: root.appendingPathComponent("GlobalLaunchDaemons", isDirectory: true)
        )
        let controller = StartupItemController()
        let enabledItems = try await scanner.scan()
        let enabledItem = try XCTUnwrap(enabledItems.first)

        let disabledURL = try controller.disable(enabledItem)

        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: disabledURL.path))
        XCTAssertEqual(disabledURL.lastPathComponent, "com.example.agent.plist.mymacclean-disabled")

        let disabledItems = try await scanner.scan()
        let disabledItem = try XCTUnwrap(disabledItems.first)
        let enabledURL = try controller.enable(disabledItem)

        XCTAssertEqual(enabledURL.resolvingSymlinksInPath(), plistURL.resolvingSymlinksInPath())
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: disabledURL.path))
    }

    func testControllerRefusesSystemWideItems() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "startup-controller-system")
        let globalLaunchDaemons = root.appendingPathComponent("GlobalLaunchDaemons", isDirectory: true)
        try writeLaunchPlist(
            named: "com.example.daemon.plist",
            in: globalLaunchDaemons,
            values: [
                "Label": "com.example.daemon",
                "Program": "/bin/echo"
            ]
        )

        let scanner = StartupItemScanner(
            userLaunchAgentsURL: root.appendingPathComponent("UserLaunchAgents", isDirectory: true),
            globalLaunchAgentsURL: root.appendingPathComponent("GlobalLaunchAgents", isDirectory: true),
            globalLaunchDaemonsURL: globalLaunchDaemons
        )
        let systemItems = try await scanner.scan()
        let systemItem = try XCTUnwrap(systemItems.first)
        let controller = StartupItemController()

        XCTAssertThrowsError(try controller.disable(systemItem)) { error in
            XCTAssertEqual(error as? StartupItemControllerError, .readOnlyItem)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: systemItem.plistURL.path))
    }

    @discardableResult
    private func writeLaunchPlist(named name: String, in directory: URL, values: [String: Any]) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}
