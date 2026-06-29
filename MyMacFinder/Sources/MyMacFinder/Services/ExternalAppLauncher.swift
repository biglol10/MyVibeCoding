import AppKit
import Foundation
import UniformTypeIdentifiers

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
    private let workspace: NSWorkspace

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public func openDefault(_ url: URL) {
        workspace.open(url)
    }

    public func open(_ urls: [URL], with application: OpenWithApplication) async throws {
        try await open(urls.map(\.standardizedFileURL), withApplicationAt: application.url)
    }

    public func openTerminal(at directory: URL) async throws {
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: terminalURL.path) else {
            throw ExplorerError.readFailed("Terminal.app was not found.")
        }
        try await open([directory.standardizedFileURL], withApplicationAt: terminalURL)
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
            workspace.open(
                urls,
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { _, error in
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
