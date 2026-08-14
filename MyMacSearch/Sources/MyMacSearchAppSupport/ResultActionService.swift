import AppKit
import Foundation
import MyMacSearchCore

public enum ResultAction: String, CaseIterable, Sendable {
    case open
    case revealInFinder
    case copyPath
    case openInTerminal
    case openInMyMacFinder
}

public enum ResultPathStatus: Equatable, Sendable {
    case missing
    case file
    case directory
}

public enum ResultActionError: Error, LocalizedError, Equatable, Sendable {
    case missingPath(String)
    case openFailed(String)
    case revealFailed(String)
    case copyFailed
    case terminalNotFound
    case myMacFinderNotFound
    case incompatibleMyMacFinder
    case launchFailed(application: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingPath(let path):
            return "The selected path is no longer available: \(path)"
        case .openFailed(let path):
            return "No application could open: \(path)"
        case .revealFailed(let path):
            return "Finder could not reveal: \(path)"
        case .copyFailed:
            return "The path could not be copied to the clipboard."
        case .terminalNotFound:
            return "Terminal.app could not be found."
        case .myMacFinderNotFound:
            return "MyMacFinder.app could not be found."
        case .incompatibleMyMacFinder:
            return "The installed MyMacFinder does not support opening a folder from MyMacSearch."
        case .launchFailed(let application, let message):
            return "\(application) could not be opened: \(message)"
        }
    }
}

@MainActor
public protocol ResultActionEnvironment: AnyObject {
    func pathStatus(at url: URL) -> ResultPathStatus
    func open(_ url: URL) -> Bool
    func reveal(_ url: URL) -> Bool
    func copyPath(_ path: String) -> Bool
    func applicationURL(bundleIdentifier: String) -> URL?
    func hasCapability(_ key: String, applicationURL: URL) -> Bool
    func launch(_ urls: [URL], withApplicationAt applicationURL: URL) async throws
}

@MainActor
public final class ResultActionService {
    public static let terminalBundleIdentifier = "com.apple.Terminal"
    public static let myMacFinderBundleIdentifier = "com.biglol.MyMacFinder"
    public static let myMacFinderCapabilityKey = "MyMacFinderSupportsExternalFolderOpen"

    private let environment: any ResultActionEnvironment
    private let onMissingPath: @MainActor (String) -> Void

    public init(
        environment: any ResultActionEnvironment = AppKitResultActionEnvironment(),
        onMissingPath: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.environment = environment
        self.onMissingPath = onMissingPath
    }

    public func perform(_ action: ResultAction, entry: IndexedEntry) async throws {
        let url = URL(fileURLWithPath: entry.path).standardizedFileURL
        let status = environment.pathStatus(at: url)
        guard status != .missing else {
            onMissingPath(url.path)
            throw ResultActionError.missingPath(url.path)
        }

        switch action {
        case .open:
            guard environment.open(url) else {
                throw ResultActionError.openFailed(url.path)
            }
        case .revealInFinder:
            guard environment.reveal(url) else {
                throw ResultActionError.revealFailed(url.path)
            }
        case .copyPath:
            guard environment.copyPath(url.path) else {
                throw ResultActionError.copyFailed
            }
        case .openInTerminal:
            guard let applicationURL = environment.applicationURL(
                bundleIdentifier: Self.terminalBundleIdentifier
            ) else {
                throw ResultActionError.terminalNotFound
            }
            try await launch(
                applicationName: "Terminal",
                target: directoryTarget(for: url, status: status),
                applicationURL: applicationURL
            )
        case .openInMyMacFinder:
            guard let applicationURL = environment.applicationURL(
                bundleIdentifier: Self.myMacFinderBundleIdentifier
            ) else {
                throw ResultActionError.myMacFinderNotFound
            }
            guard environment.hasCapability(
                Self.myMacFinderCapabilityKey,
                applicationURL: applicationURL
            ) else {
                throw ResultActionError.incompatibleMyMacFinder
            }
            try await launch(
                applicationName: "MyMacFinder",
                target: directoryTarget(for: url, status: status),
                applicationURL: applicationURL
            )
        }
    }

    private func directoryTarget(for url: URL, status: ResultPathStatus) -> URL {
        status == .directory ? url : url.deletingLastPathComponent()
    }

    private func launch(
        applicationName: String,
        target: URL,
        applicationURL: URL
    ) async throws {
        do {
            try await environment.launch([target], withApplicationAt: applicationURL)
        } catch {
            throw ResultActionError.launchFailed(
                application: applicationName,
                message: error.localizedDescription
            )
        }
    }
}

@MainActor
public final class AppKitResultActionEnvironment: ResultActionEnvironment {
    private let workspace: NSWorkspace
    private let fileManager: FileManager
    private let pasteboard: NSPasteboard

    public init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default,
        pasteboard: NSPasteboard = .general
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
        self.pasteboard = pasteboard
    }

    public func pathStatus(at url: URL) -> ResultPathStatus {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }
        return isDirectory.boolValue ? .directory : .file
    }

    public func open(_ url: URL) -> Bool {
        workspace.open(url)
    }

    public func reveal(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        workspace.activateFileViewerSelecting([url])
        return true
    }

    public func copyPath(_ path: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(path, forType: .string)
    }

    public func applicationURL(bundleIdentifier: String) -> URL? {
        if bundleIdentifier == ResultActionService.terminalBundleIdentifier {
            let terminalURL = URL(
                fileURLWithPath: "/System/Applications/Utilities/Terminal.app",
                isDirectory: true
            )
            if fileManager.fileExists(atPath: terminalURL.path) {
                return terminalURL
            }
        }
        return workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    public func hasCapability(_ key: String, applicationURL: URL) -> Bool {
        Bundle(url: applicationURL)?.object(forInfoDictionaryKey: key) as? Bool == true
    }

    public func launch(_ urls: [URL], withApplicationAt applicationURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = true
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
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
}
