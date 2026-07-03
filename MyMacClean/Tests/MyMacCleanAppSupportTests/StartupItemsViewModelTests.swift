import XCTest
@testable import MyMacCleanAppSupport
@testable import MyMacCleanCore

@MainActor
final class StartupItemsViewModelTests: XCTestCase {
    func testListPresentationUsesCompactBadgesForNarrowRows() {
        let userItem = makeStartupItem(
            label: "com.example.user-agent",
            scope: .userLaunchAgent,
            state: .enabled
        )
        let globalAgent = makeStartupItem(
            label: "com.example.global-agent",
            scope: .globalLaunchAgent,
            state: .enabled
        )
        let daemon = makeStartupItem(
            label: "com.example.daemon",
            scope: .globalLaunchDaemon,
            state: .disabled
        )

        XCTAssertEqual(StartupItemListPresentation(item: userItem).stateBadgeTitle, "Enabled")
        XCTAssertEqual(StartupItemListPresentation(item: userItem).scopeBadgeTitle, "User")
        XCTAssertNil(StartupItemListPresentation(item: userItem).attentionBadgeTitle)

        XCTAssertEqual(StartupItemListPresentation(item: globalAgent).scopeBadgeTitle, "Global")
        XCTAssertEqual(StartupItemListPresentation(item: globalAgent).attentionBadgeTitle, "Read-only")

        XCTAssertEqual(StartupItemListPresentation(item: daemon).stateBadgeTitle, "Disabled")
        XCTAssertEqual(StartupItemListPresentation(item: daemon).scopeBadgeTitle, "Daemon")
        XCTAssertEqual(StartupItemListPresentation(item: daemon).attentionBadgeTitle, "Read-only")
    }

    func testListPresentationShowsMissingTargetBeforeReadOnly() {
        let item = makeStartupItem(
            label: "com.example.missing-daemon",
            scope: .globalLaunchDaemon,
            state: .enabled,
            targetURL: URL(fileURLWithPath: "/missing/tool"),
            targetExists: false
        )

        XCTAssertEqual(StartupItemListPresentation(item: item).attentionBadgeTitle, "Missing")
    }

    func testScanLoadsItemsAndSelectsFirstVisibleItem() async throws {
        let root = try temporaryDirectory(named: "startup-viewmodel-scan")
        let userLaunchAgents = root.appendingPathComponent("UserLaunchAgents", isDirectory: true)
        try writeLaunchPlist(
            named: "com.example.alpha.plist",
            in: userLaunchAgents,
            values: [
                "Label": "com.example.alpha",
                "Program": "/bin/echo"
            ]
        )

        let viewModel = StartupItemsViewModel(
            scanner: StartupItemScanner(
                userLaunchAgentsURL: userLaunchAgents,
                globalLaunchAgentsURL: root.appendingPathComponent("GlobalLaunchAgents", isDirectory: true),
                globalLaunchDaemonsURL: root.appendingPathComponent("GlobalLaunchDaemons", isDirectory: true)
            )
        )

        await viewModel.scan()

        XCTAssertTrue(viewModel.hasScanned)
        XCTAssertEqual(viewModel.items.map(\.label), ["com.example.alpha"])
        XCTAssertEqual(viewModel.selectedItem?.label, "com.example.alpha")
        XCTAssertEqual(viewModel.visibleItems.map(\.label), ["com.example.alpha"])
    }

    func testDisableAndEnableSelectedUserItemRefreshesState() async throws {
        let root = try temporaryDirectory(named: "startup-viewmodel-toggle")
        let userLaunchAgents = root.appendingPathComponent("UserLaunchAgents", isDirectory: true)
        let plistURL = try writeLaunchPlist(
            named: "com.example.toggle.plist",
            in: userLaunchAgents,
            values: [
                "Label": "com.example.toggle",
                "Program": "/bin/echo"
            ]
        )

        let viewModel = StartupItemsViewModel(
            scanner: StartupItemScanner(
                userLaunchAgentsURL: userLaunchAgents,
                globalLaunchAgentsURL: root.appendingPathComponent("GlobalLaunchAgents", isDirectory: true),
                globalLaunchDaemonsURL: root.appendingPathComponent("GlobalLaunchDaemons", isDirectory: true)
            ),
            controller: StartupItemController()
        )

        await viewModel.scan()
        await viewModel.disableSelectedItem()

        XCTAssertEqual(viewModel.selectedItem?.state, .disabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path + ".mymacclean-disabled"))

        await viewModel.enableSelectedItem()

        XCTAssertEqual(viewModel.selectedItem?.state, .enabled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path + ".mymacclean-disabled"))
    }

    func testSearchMovesSelectionToFirstVisibleItem() async throws {
        let root = try temporaryDirectory(named: "startup-viewmodel-search")
        let userLaunchAgents = root.appendingPathComponent("UserLaunchAgents", isDirectory: true)
        try writeLaunchPlist(
            named: "com.example.alpha.plist",
            in: userLaunchAgents,
            values: [
                "Label": "com.example.alpha",
                "Program": "/bin/echo"
            ]
        )
        try writeLaunchPlist(
            named: "com.example.beta.plist",
            in: userLaunchAgents,
            values: [
                "Label": "com.example.beta",
                "Program": "/bin/echo"
            ]
        )

        let viewModel = StartupItemsViewModel(
            scanner: StartupItemScanner(
                userLaunchAgentsURL: userLaunchAgents,
                globalLaunchAgentsURL: root.appendingPathComponent("GlobalLaunchAgents", isDirectory: true),
                globalLaunchDaemonsURL: root.appendingPathComponent("GlobalLaunchDaemons", isDirectory: true)
            )
        )

        await viewModel.scan()
        XCTAssertEqual(viewModel.selectedItem?.label, "com.example.alpha")

        viewModel.searchText = "beta"

        XCTAssertEqual(viewModel.visibleItems.map(\.label), ["com.example.beta"])
        XCTAssertEqual(viewModel.selectedItem?.label, "com.example.beta")
    }

    func testSystemItemsAreReadOnly() async throws {
        let root = try temporaryDirectory(named: "startup-viewmodel-readonly")
        let globalLaunchDaemons = root.appendingPathComponent("GlobalLaunchDaemons", isDirectory: true)
        try writeLaunchPlist(
            named: "com.example.daemon.plist",
            in: globalLaunchDaemons,
            values: [
                "Label": "com.example.daemon",
                "Program": "/bin/echo"
            ]
        )

        let viewModel = StartupItemsViewModel(
            scanner: StartupItemScanner(
                userLaunchAgentsURL: root.appendingPathComponent("UserLaunchAgents", isDirectory: true),
                globalLaunchAgentsURL: root.appendingPathComponent("GlobalLaunchAgents", isDirectory: true),
                globalLaunchDaemonsURL: globalLaunchDaemons
            )
        )

        await viewModel.scan()
        await viewModel.disableSelectedItem()

        XCTAssertEqual(viewModel.selectedItem?.scope, .globalLaunchDaemon)
        XCTAssertEqual(viewModel.errorMessage, StartupItemControllerError.readOnlyItem.localizedDescription)
        XCTAssertTrue(FileManager.default.fileExists(atPath: globalLaunchDaemons.appendingPathComponent("com.example.daemon.plist").path))
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanAppSupportTests-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    private func makeStartupItem(
        label: String,
        scope: StartupItemScope,
        state: StartupItemState,
        targetURL: URL? = URL(fileURLWithPath: "/bin/echo"),
        targetExists: Bool = true
    ) -> StartupItem {
        StartupItem(
            label: label,
            plistURL: URL(fileURLWithPath: "/Library/LaunchAgents/\(label).plist"),
            scope: scope,
            state: state,
            program: "/bin/echo",
            programArguments: [],
            runAtLoad: true,
            keepAliveSummary: nil,
            startInterval: nil,
            startCalendarSummary: nil,
            disabledFlag: state == .disabled,
            disabledByRename: false,
            targetURL: targetURL,
            targetExists: targetExists,
            ownerName: "Example",
            ownerEvidence: "Test fixture"
        )
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
