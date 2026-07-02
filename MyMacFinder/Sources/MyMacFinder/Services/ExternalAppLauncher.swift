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

public struct ExternalCommandInvocation: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let failureMessage: String

    public init(executableURL: URL, arguments: [String], failureMessage: String) {
        self.executableURL = executableURL.standardizedFileURL
        self.arguments = arguments
        self.failureMessage = failureMessage
    }
}

@MainActor
public protocol ExternalCommandRunning: AnyObject {
    func run(_ invocation: ExternalCommandInvocation) async throws
}

public final class ProcessExternalCommandRunner: ExternalCommandRunning {
    public init() {}

    public func run(_ invocation: ExternalCommandInvocation) async throws {
        do {
            let status = try await Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = invocation.executableURL
                process.arguments = invocation.arguments
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            }.value

            guard status == 0 else {
                throw ExplorerError.externalCommandFailed(invocation.failureMessage)
            }
        } catch let error as ExplorerError {
            throw error
        } catch {
            throw ExplorerError.externalCommandFailed(invocation.failureMessage)
        }
    }
}

@MainActor
public final class AppKitExternalAppLauncher: ExternalAppLaunching {
    private static let vscodeFailureMessage = "Visual Studio Code is not installed or the code command was not found."

    private let workspace: any WorkspaceApplicationOpening
    private let terminalApplicationURL: URL
    private let commandRunner: any ExternalCommandRunning
    private let codeCommandShellURL: URL

    public init(
        workspace: any WorkspaceApplicationOpening = NSWorkspace.shared,
        terminalApplicationURL: URL = URL(
            fileURLWithPath: "/System/Applications/Utilities/Terminal.app",
            isDirectory: true
        ),
        commandRunner: any ExternalCommandRunning = ProcessExternalCommandRunner(),
        codeCommandShellURL: URL? = nil
    ) {
        self.workspace = workspace
        self.terminalApplicationURL = terminalApplicationURL.standardizedFileURL
        self.commandRunner = commandRunner
        self.codeCommandShellURL = (codeCommandShellURL ?? Self.defaultShellURL()).standardizedFileURL
    }

    public func openDefault(_ url: URL) {
        workspace.open(url)
    }

    public func open(_ urls: [URL], with application: OpenWithApplication) async throws {
        try await open(urls.map(\.standardizedFileURL), withApplicationAt: application.url)
    }

    public func openTerminal(at directory: URL) async throws {
        guard FileManager.default.fileExists(atPath: terminalApplicationURL.path) else {
            throw ExplorerError.externalCommandFailed("Terminal.app was not found.")
        }
        openWithoutWaitingForCompletion(
            [directory.standardizedFileURL],
            withApplicationAt: terminalApplicationURL
        )
    }

    public func openVSCode(at target: URL) async throws {
        if let appURL = vscodeApplicationURL() {
            try await open([target.standardizedFileURL], withApplicationAt: appURL)
            return
        }

        try await commandRunner.run(
            ExternalCommandInvocation(
                executableURL: codeCommandShellURL,
                arguments: [
                    "-lc",
                    "exec code \"$1\"",
                    "mymacfinder-code",
                    target.standardizedFileURL.path
                ],
                failureMessage: Self.vscodeFailureMessage
            )
        )
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
        let configuration = makeOpenConfiguration()

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

    private func openWithoutWaitingForCompletion(_ urls: [URL], withApplicationAt applicationURL: URL) {
        workspace.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: makeOpenConfiguration(),
            completionHandler: nil
        )
    }

    private func makeOpenConfiguration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = true
        return configuration
    }

    private func vscodeApplicationURL() -> URL? {
        workspace.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode")?.standardizedFileURL
    }

    private static func defaultShellURL() -> URL {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return URL(fileURLWithPath: shellPath)
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
