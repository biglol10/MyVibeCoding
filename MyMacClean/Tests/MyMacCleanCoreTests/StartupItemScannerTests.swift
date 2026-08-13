import XCTest
@testable import MyMacCleanCore

final class StartupItemScannerTests: XCTestCase {
    func testScannerParsesLaunchAgentFieldsAndInfersTarget() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "startup-items-scan")
        let userLaunchAgents = root.appendingPathComponent("UserLaunchAgents", isDirectory: true)
        let executable = root.appendingPathComponent("Applications/Example.app/Contents/MacOS/Example")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("run".utf8).write(to: executable)

        try writeLaunchPlist(
            named: "com.example.agent.plist",
            in: userLaunchAgents,
            values: [
                "Label": "com.example.agent",
                "Program": executable.path,
                "ProgramArguments": [executable.path, "--background"],
                "RunAtLoad": true,
                "KeepAlive": true,
                "StartInterval": 600
            ]
        )

        let results = try await StartupItemScanner(
            userLaunchAgentsURL: userLaunchAgents,
            globalLaunchAgentsURL: root.appendingPathComponent("GlobalLaunchAgents", isDirectory: true),
            globalLaunchDaemonsURL: root.appendingPathComponent("GlobalLaunchDaemons", isDirectory: true)
        ).scan()

        XCTAssertEqual(results.count, 1)
        let item = try XCTUnwrap(results.first)
        XCTAssertEqual(item.label, "com.example.agent")
        XCTAssertEqual(item.scope, .userLaunchAgent)
        XCTAssertEqual(item.state, .enabled)
        XCTAssertEqual(item.program, executable.path)
        XCTAssertEqual(item.programArguments, [executable.path, "--background"])
        XCTAssertEqual(item.runAtLoad, true)
        XCTAssertEqual(item.keepAliveSummary, "true")
        XCTAssertEqual(item.startInterval, 600)
        XCTAssertEqual(item.targetURL, executable)
        XCTAssertEqual(item.targetExists, true)
        XCTAssertEqual(item.ownerName, "Example")
        XCTAssertTrue(item.isEditable)
        XCTAssertFalse(item.isReadOnly)
    }

    func testScannerReadsDisabledRenamedUserLaunchAgent() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "startup-items-disabled")
        let userLaunchAgents = root.appendingPathComponent("UserLaunchAgents", isDirectory: true)
        let plistURL = try writeLaunchPlist(
            named: "com.example.disabled.plist.mymacclean-disabled",
            in: userLaunchAgents,
            values: [
                "Label": "com.example.disabled",
                "ProgramArguments": ["/bin/echo", "hello"]
            ]
        )

        let results = try await StartupItemScanner(
            userLaunchAgentsURL: userLaunchAgents,
            globalLaunchAgentsURL: root.appendingPathComponent("GlobalLaunchAgents", isDirectory: true),
            globalLaunchDaemonsURL: root.appendingPathComponent("GlobalLaunchDaemons", isDirectory: true)
        ).scan()

        let item = try XCTUnwrap(results.first)
        XCTAssertEqual(item.plistURL.resolvingSymlinksInPath(), plistURL.resolvingSymlinksInPath())
        XCTAssertEqual(item.state, .disabled)
        XCTAssertEqual(item.targetURL?.path, "/bin/echo")
        XCTAssertTrue(item.isEditable)
    }

    func testScannerSkipsMalformedPlists() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "startup-items-malformed")
        let userLaunchAgents = root.appendingPathComponent("UserLaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: userLaunchAgents, withIntermediateDirectories: true)
        try Data("not a plist".utf8)
            .write(to: userLaunchAgents.appendingPathComponent("com.example.bad.plist"))

        try writeLaunchPlist(
            named: "com.example.good.plist",
            in: userLaunchAgents,
            values: [
                "Label": "com.example.good",
                "Program": "/bin/echo"
            ]
        )

        let result = await StartupItemScanner(
            userLaunchAgentsURL: userLaunchAgents,
            globalLaunchAgentsURL: root.appendingPathComponent("GlobalLaunchAgents", isDirectory: true),
            globalLaunchDaemonsURL: root.appendingPathComponent("GlobalLaunchDaemons", isDirectory: true)
        ).scanWithCoverage()

        XCTAssertEqual(result.value.map(\.label), ["com.example.good"])
        XCTAssertEqual(
            result.issues.map(\.path),
            [userLaunchAgents.appendingPathComponent("com.example.bad.plist").path]
        )
    }

    func testScannerClassifiesSystemLocationsAsReadOnlyAndMissingTarget() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "startup-items-system")
        let globalLaunchAgents = root.appendingPathComponent("GlobalLaunchAgents", isDirectory: true)
        let globalLaunchDaemons = root.appendingPathComponent("GlobalLaunchDaemons", isDirectory: true)
        let missingTarget = root.appendingPathComponent("missing-tool")

        try writeLaunchPlist(
            named: "com.example.globalagent.plist",
            in: globalLaunchAgents,
            values: [
                "Label": "com.example.globalagent",
                "Program": missingTarget.path,
                "Disabled": true
            ]
        )
        try writeLaunchPlist(
            named: "com.example.daemon.plist",
            in: globalLaunchDaemons,
            values: [
                "Label": "com.example.daemon",
                "ProgramArguments": [missingTarget.path, "--daemon"]
            ]
        )

        let results = try await StartupItemScanner(
            userLaunchAgentsURL: root.appendingPathComponent("UserLaunchAgents", isDirectory: true),
            globalLaunchAgentsURL: globalLaunchAgents,
            globalLaunchDaemonsURL: globalLaunchDaemons
        ).scan()

        XCTAssertEqual(results.map(\.scope), [.globalLaunchAgent, .globalLaunchDaemon])
        XCTAssertTrue(results.allSatisfy(\.isReadOnly))
        XCTAssertTrue(results.allSatisfy(\.hasMissingTarget))
        XCTAssertEqual(results.first(where: { $0.scope == .globalLaunchAgent })?.state, .disabled)
        XCTAssertEqual(results.first(where: { $0.scope == .globalLaunchDaemon })?.state, .enabled)
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
