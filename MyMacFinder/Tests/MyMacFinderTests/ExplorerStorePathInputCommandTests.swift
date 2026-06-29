import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerStorePathInputCommandTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderPathInputCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testCmdInputOpensTerminalWhenRelativePathDoesNotExist() async {
        let launcher = SpyExternalAppLauncher()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            directoryWatcher: nil,
            externalAppLauncher: launcher
        )

        await store.resolveAndNavigate("cmd")

        XCTAssertEqual(launcher.terminalDirectories, [tempDirectory.standardizedFileURL])
        XCTAssertEqual(store.activePane.currentURL, tempDirectory.standardizedFileURL)
        XCTAssertNil(store.visibleError)
    }

    @MainActor
    func testCodeDotInputOpensCurrentDirectoryInVSCode() async {
        let launcher = SpyExternalAppLauncher()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            directoryWatcher: nil,
            externalAppLauncher: launcher
        )

        await store.resolveAndNavigate("code .")

        XCTAssertEqual(launcher.vsCodeTargets, [tempDirectory.standardizedFileURL])
        XCTAssertEqual(store.activePane.currentURL, tempDirectory.standardizedFileURL)
        XCTAssertNil(store.visibleError)
    }

    @MainActor
    func testExistingRelativePathWinsOverCommandAlias() async throws {
        let commandNamedFolder = tempDirectory.appendingPathComponent("cmd", isDirectory: true)
        try FileManager.default.createDirectory(at: commandNamedFolder, withIntermediateDirectories: true)
        let launcher = SpyExternalAppLauncher()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            directoryWatcher: nil,
            externalAppLauncher: launcher
        )

        await store.resolveAndNavigate("cmd")

        XCTAssertEqual(store.activePane.currentURL, commandNamedFolder.standardizedFileURL)
        XCTAssertTrue(launcher.terminalDirectories.isEmpty)
    }

    @MainActor
    func testOpenInTerminalCommandUsesSelectedFolder() async throws {
        let folder = tempDirectory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let launcher = SpyExternalAppLauncher()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            directoryWatcher: nil,
            externalAppLauncher: launcher
        )
        await store.refresh()
        store.updateSelection([folder.standardizedFileURL])

        await store.perform(.openInTerminal)

        XCTAssertEqual(launcher.terminalDirectories, [folder.standardizedFileURL])
    }

    @MainActor
    func testOpenSelectedWithApplicationUsesSelectedURLs() async throws {
        let file = tempDirectory.appendingPathComponent("note.txt")
        try "note".write(to: file, atomically: true, encoding: .utf8)
        let application = OpenWithApplication(
            url: URL(fileURLWithPath: "/Applications/TextEdit.app", isDirectory: true),
            title: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit"
        )
        let launcher = SpyExternalAppLauncher()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            directoryWatcher: nil,
            externalAppLauncher: launcher
        )
        await store.refresh()
        store.updateSelection([file.standardizedFileURL])

        await store.openSelected(with: application)

        XCTAssertEqual(launcher.openedApplications.map(\.urls), [[file.standardizedFileURL]])
        XCTAssertEqual(launcher.openedApplications.map(\.application), [application])
    }
}

@MainActor
private final class SpyExternalAppLauncher: ExternalAppLaunching {
    var defaultOpenedURLs: [URL] = []
    var terminalDirectories: [URL] = []
    var vsCodeTargets: [URL] = []
    var openedApplications: [(urls: [URL], application: OpenWithApplication)] = []
    var applications: [OpenWithApplication] = []

    func openDefault(_ url: URL) {
        defaultOpenedURLs.append(url.standardizedFileURL)
    }

    func open(_ urls: [URL], with application: OpenWithApplication) async throws {
        openedApplications.append((urls.map(\.standardizedFileURL), application))
    }

    func openTerminal(at directory: URL) async throws {
        terminalDirectories.append(directory.standardizedFileURL)
    }

    func openVSCode(at target: URL) async throws {
        vsCodeTargets.append(target.standardizedFileURL)
    }

    func applications(toOpen url: URL) -> [OpenWithApplication] {
        applications
    }
}
