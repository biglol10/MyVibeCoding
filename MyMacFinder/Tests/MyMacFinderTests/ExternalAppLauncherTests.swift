import AppKit
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import MyMacFinder

final class ExternalAppLauncherTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        let root = try XCTUnwrap(tempDirectory)
        try FileManager.default.removeItem(at: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        tempDirectory = nil
    }

    @MainActor
    func testOpenDefaultThrowsWhenWorkspaceRejectsURL() {
        let workspace = DefaultOpenWorkspaceOpener(result: false)
        let launcher = AppKitExternalAppLauncher(workspace: workspace)
        let file = URL(fileURLWithPath: "/tmp/unopenable.fixture")

        XCTAssertThrowsError(try launcher.openDefault(file)) { error in
            XCTAssertEqual(
                error as? ExplorerError,
                .externalCommandFailed("No application could open: /tmp/unopenable.fixture")
            )
        }
    }

    @MainActor
    func testOpenTerminalDoesNotWaitForWorkspaceCompletionCallbacks() async throws {
        let workspace = DuplicateCompletionWorkspaceOpener()
        let terminalURL = tempDirectory.appendingPathComponent("FakeTerminal.app", isDirectory: true)
        try FileManager.default.createDirectory(at: terminalURL, withIntermediateDirectories: true)
        let directory = URL(fileURLWithPath: "/Users/example/Project", isDirectory: true)
        let launcher = AppKitExternalAppLauncher(
            workspace: workspace,
            terminalApplicationURL: terminalURL
        )

        try await launcher.openTerminal(at: directory)

        XCTAssertEqual(workspace.openCalls.map(\.urls), [[directory.standardizedFileURL]])
        XCTAssertEqual(workspace.openCalls.map(\.applicationURL), [terminalURL.standardizedFileURL])
    }

    @MainActor
    func testOpenTerminalDoesNotSurfaceWorkspaceCompletionErrors() async throws {
        let workspace = CompletionErrorWorkspaceOpener()
        let terminalURL = tempDirectory.appendingPathComponent("FakeTerminal.app", isDirectory: true)
        try FileManager.default.createDirectory(at: terminalURL, withIntermediateDirectories: true)
        let directory = URL(fileURLWithPath: "/Users/example/Project", isDirectory: true)
        let launcher = AppKitExternalAppLauncher(
            workspace: workspace,
            terminalApplicationURL: terminalURL
        )

        try await launcher.openTerminal(at: directory)

        XCTAssertEqual(workspace.openCalls.map(\.urls), [[directory.standardizedFileURL]])
        XCTAssertEqual(workspace.openCalls.map(\.applicationURL), [terminalURL.standardizedFileURL])
    }

    @MainActor
    func testOpenWithIgnoresDuplicateWorkspaceCompletionCallbacks() async throws {
        let workspace = DuplicateCompletionWorkspaceOpener()
        let file = URL(fileURLWithPath: "/Users/example/report.pdf")
        let preview = OpenWithApplication(
            url: URL(fileURLWithPath: "/Applications/Preview.app", isDirectory: true),
            title: "Preview",
            bundleIdentifier: "com.apple.Preview"
        )
        let launcher = AppKitExternalAppLauncher(workspace: workspace)

        try await launcher.open([file], with: preview)

        XCTAssertEqual(workspace.openCalls.map(\.urls), [[file.standardizedFileURL]])
        XCTAssertEqual(workspace.openCalls.map(\.applicationURL), [preview.url])
    }

    @MainActor
    func testOpenVSCodeAppIgnoresDuplicateWorkspaceCompletionCallbacks() async throws {
        let vscodeURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app", isDirectory: true)
        let workspace = DuplicateCompletionWorkspaceOpener(applicationURLsByBundleIdentifier: [
            "com.microsoft.VSCode": vscodeURL
        ])
        let target = URL(fileURLWithPath: "/Users/example/Project", isDirectory: true)
        let launcher = AppKitExternalAppLauncher(workspace: workspace)

        try await launcher.openVSCode(at: target)

        XCTAssertEqual(workspace.openCalls.map(\.urls), [[target.standardizedFileURL]])
        XCTAssertEqual(workspace.openCalls.map(\.applicationURL), [vscodeURL.standardizedFileURL])
    }

    @MainActor
    func testOpenVSCodeFallsBackToCodeCommandThroughUserShell() async throws {
        let workspace = DuplicateCompletionWorkspaceOpener()
        let commandRunner = RecordingExternalCommandRunner()
        let target = URL(fileURLWithPath: "/Users/example/Project", isDirectory: true)
        let shellURL = URL(fileURLWithPath: "/bin/zsh")
        let launcher = AppKitExternalAppLauncher(
            workspace: workspace,
            commandRunner: commandRunner,
            codeCommandShellURL: shellURL
        )

        try await launcher.openVSCode(at: target)

        XCTAssertTrue(workspace.openCalls.isEmpty)
        XCTAssertEqual(
            commandRunner.invocations,
            [
                ExternalCommandInvocation(
                    executableURL: shellURL,
                    arguments: [
                        "-lc",
                        "exec code \"$1\"",
                        "mymacfinder-code",
                        target.standardizedFileURL.path
                    ],
                    failureMessage: "Visual Studio Code is not installed or the code command was not found."
                )
            ]
        )
    }

    @MainActor
    func testMissingTerminalIsNotReportedAsReadFailure() async throws {
        let workspace = DuplicateCompletionWorkspaceOpener()
        let missingTerminalURL = tempDirectory.appendingPathComponent("MissingTerminal.app", isDirectory: true)
        let directory = URL(fileURLWithPath: "/Users/example/Project", isDirectory: true)
        let launcher = AppKitExternalAppLauncher(
            workspace: workspace,
            terminalApplicationURL: missingTerminalURL
        )

        do {
            try await launcher.openTerminal(at: directory)
            XCTFail("Expected opening a missing Terminal app to fail")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .externalCommandFailed("Terminal.app was not found."))
        }
    }
}

private final class RecordingExternalCommandRunner: ExternalCommandRunning {
    var invocations: [ExternalCommandInvocation] = []

    func run(_ invocation: ExternalCommandInvocation) async throws {
        invocations.append(invocation)
    }
}

@MainActor
private final class DefaultOpenWorkspaceOpener: WorkspaceApplicationOpening {
    private let result: Bool

    init(result: Bool) {
        self.result = result
    }

    func open(_ url: URL) -> Bool {
        result
    }

    func open(
        _ urls: [URL],
        withApplicationAt applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completionHandler: ((NSRunningApplication?, (any Error)?) -> Void)?
    ) {}

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        nil
    }

    func urlsForApplications(toOpen contentType: UTType) -> [URL] {
        []
    }
}

@MainActor
private final class DuplicateCompletionWorkspaceOpener: WorkspaceApplicationOpening {
    struct OpenCall: Equatable {
        let urls: [URL]
        let applicationURL: URL
    }

    var openCalls: [OpenCall] = []
    private let applicationURLsByBundleIdentifier: [String: URL]

    init(applicationURLsByBundleIdentifier: [String: URL] = [:]) {
        self.applicationURLsByBundleIdentifier = applicationURLsByBundleIdentifier
    }

    func open(_ url: URL) -> Bool {
        true
    }

    func open(
        _ urls: [URL],
        withApplicationAt applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completionHandler: ((NSRunningApplication?, (any Error)?) -> Void)?
    ) {
        openCalls.append(OpenCall(urls: urls.map(\.standardizedFileURL), applicationURL: applicationURL.standardizedFileURL))
        completionHandler?(nil, nil)
        completionHandler?(nil, NSError(domain: "duplicate", code: 1))
    }

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        applicationURLsByBundleIdentifier[bundleIdentifier]?.standardizedFileURL
    }

    func urlsForApplications(toOpen contentType: UTType) -> [URL] {
        []
    }
}

@MainActor
private final class CompletionErrorWorkspaceOpener: WorkspaceApplicationOpening {
    struct OpenCall: Equatable {
        let urls: [URL]
        let applicationURL: URL
    }

    var openCalls: [OpenCall] = []

    func open(_ url: URL) -> Bool {
        true
    }

    func open(
        _ urls: [URL],
        withApplicationAt applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completionHandler: ((NSRunningApplication?, (any Error)?) -> Void)?
    ) {
        openCalls.append(OpenCall(urls: urls.map(\.standardizedFileURL), applicationURL: applicationURL.standardizedFileURL))
        completionHandler?(nil, NSError(domain: "terminal-open", code: 1))
    }

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        nil
    }

    func urlsForApplications(toOpen contentType: UTType) -> [URL] {
        []
    }
}
