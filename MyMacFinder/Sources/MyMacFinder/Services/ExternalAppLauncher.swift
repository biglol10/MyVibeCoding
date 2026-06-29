import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
public protocol WorkspaceApplicationOpening: AnyObject {
    @discardableResult
    func open(_ url: URL) -> Bool
    func open(
        _ urls: [URL],
        withApplicationAt applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completionHandler: ((NSRunningApplication?, (any Error)?) -> Void)?
    )
    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL?
    func urlsForApplications(toOpen contentType: UTType) -> [URL]
}

extension NSWorkspace: WorkspaceApplicationOpening {}

@MainActor
public protocol ExternalAppLaunching: AnyObject {
    func openDefault(_ url: URL)
    func open(_ urls: [URL], with application: OpenWithApplication) async throws
    func openTerminal(at directory: URL) async throws
    func openVSCode(at target: URL) async throws
    func applications(toOpen url: URL) -> [OpenWithApplication]
}

@MainActor
public final class AppKitExternalAppLauncher: ExternalAppLaunching {
    private let workspace: any WorkspaceApplicationOpening
    private let terminalApplicationURL: URL

    public init(
        workspace: any WorkspaceApplicationOpening = NSWorkspace.shared,
        terminalApplicationURL: URL = URL(
            fileURLWithPath: "/System/Applications/Utilities/Terminal.app",
            isDirectory: true
        )
    ) {
        self.workspace = workspace
        self.terminalApplicationURL = terminalApplicationURL.standardizedFileURL
    }

    public func openDefault(_ url: URL) {
        workspace.open(url)
    }

    public func open(_ urls: [URL], with application: OpenWithApplication) async throws {
        try await open(urls.map(\.standardizedFileURL), withApplicationAt: application.url)
    }

    public func openTerminal(at directory: URL) async throws {
        guard FileManager.default.fileExists(atPath: terminalApplicationURL.path) else {
            throw ExplorerError.readFailed("Terminal.app was not found.")
        }
        try await open([directory.standardizedFileURL], withApplicationAt: terminalApplicationURL)
    }

    public func openVSCode(at target: URL) async throws {
        if let appURL = vscodeApplicationURL() {
            try await open([target.standardizedFileURL], withApplicationAt: appURL)
            return
        }

        if let commandURL = vscodeCommandURL() {
            try runProcess(commandURL, arguments: [target.path])
            return
        }

        throw ExplorerError.readFailed("Visual Studio Code is not installed or the code command was not found.")
    }

    public func applications(toOpen url: URL) -> [OpenWithApplication] {
        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return []
        }

        var seen: Set<URL> = []
        return workspace.urlsForApplications(toOpen: contentType)
            .map(\.standardizedFileURL)
            .filter { seen.insert($0).inserted }
            .map(makeApplication)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func open(_ urls: [URL], withApplicationAt applicationURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = OneShotWorkspaceOpenCompletion()
            workspace.open(
                urls,
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { _, error in
                guard completion.shouldResume() else {
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func vscodeApplicationURL() -> URL? {
        if let url = workspace.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            return url.standardizedFileURL
        }

        let candidates = [
            "/Applications/Visual Studio Code.app",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Visual Studio Code.app", isDirectory: true)
                .path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads/Visual Studio Code.app", isDirectory: true)
                .path
        ]

        return candidates
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func vscodeCommandURL() -> URL? {
        [
            "/usr/local/bin/code",
            "/opt/homebrew/bin/code",
            "/usr/bin/code"
        ]
        .map { URL(fileURLWithPath: $0) }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func runProcess(_ executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()
    }

    private func makeApplication(_ url: URL) -> OpenWithApplication {
        let bundle = Bundle(url: url)
        let title = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return OpenWithApplication(
            url: url,
            title: title,
            bundleIdentifier: bundle?.bundleIdentifier
        )
    }
}

private final class OneShotWorkspaceOpenCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func shouldResume() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !didResume else {
            return false
        }
        didResume = true
        return true
    }
}
