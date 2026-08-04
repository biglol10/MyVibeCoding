import AppKit
import Darwin
import Foundation

@MainActor
public protocol ClipboardServicing {
    func copyPNGData(_ data: Data)
    func copyText(_ text: String)
}

public struct PasteboardClipboardService: ClipboardServicing {
    public init() {}

    public func copyPNGData(_ data: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }

    public func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

@MainActor
public protocol FileRevealServicing {
    func reveal(_ url: URL)
}

public struct WorkspaceFileRevealService: FileRevealServicing {
    public init() {}

    public func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

@MainActor
public protocol FileTrashServicing {
    func trash(_ url: URL, expectedIdentity: CaptureFileIdentity?) throws
}

public enum FileTrashError: LocalizedError, Equatable {
    case fileChanged
    case fileRecovered(URL)

    public var errorDescription: String? {
        switch self {
        case .fileChanged:
            return "The file changed before it could be moved to Trash."
        case let .fileRecovered(url):
            return "The file could not be moved to Trash and was recovered as \(url.lastPathComponent)."
        }
    }
}

public struct WorkspaceFileTrashService: FileTrashServicing {
    private let identityWasCheckedBeforeQuarantine: (() throws -> Void)?
    private let trashOperation: (URL) throws -> Void

    public init() {
        self.init(
            identityWasCheckedBeforeQuarantine: nil,
            trashOperation: { url in
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
        )
    }

    init(
        identityWasCheckedBeforeQuarantine: (() throws -> Void)? = nil,
        trashOperation: @escaping (URL) throws -> Void
    ) {
        self.identityWasCheckedBeforeQuarantine = identityWasCheckedBeforeQuarantine
        self.trashOperation = trashOperation
    }

    public func trash(_ url: URL, expectedIdentity: CaptureFileIdentity?) throws {
        let identity = try expectedIdentity ?? CaptureFileIdentity.existingFile(at: url)
        guard identity.matchesExistingFile(at: url) else {
            throw FileTrashError.fileChanged
        }
        try identityWasCheckedBeforeQuarantine?()

        let quarantineDirectoryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".CaptureStudio-Trash-\(UUID().uuidString)", isDirectory: true)
        let createResult = quarantineDirectoryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.mkdir(path, S_IRWXU)
        }
        guard createResult == 0 else {
            throw Self.posixError(errno)
        }
        let quarantineDirectoryIdentity = try CaptureFileIdentity.existingFile(at: quarantineDirectoryURL)
        defer {
            Self.removeDirectoryIfStillOwned(
                quarantineDirectoryURL,
                identity: quarantineDirectoryIdentity
            )
        }

        let quarantinedURL = quarantineDirectoryURL.appendingPathComponent(url.lastPathComponent)
        let moveResult = Self.renameExclusively(from: url, to: quarantinedURL)
        guard moveResult == 0 else {
            if errno == ENOENT {
                throw FileTrashError.fileChanged
            }
            throw Self.posixError(errno)
        }

        let quarantinedIdentity: CaptureFileIdentity
        do {
            quarantinedIdentity = try CaptureFileIdentity.existingFile(at: quarantinedURL)
        } catch {
            if let recoveryURL = Self.restoreOrRecover(from: quarantinedURL, to: url), recoveryURL != url {
                throw FileTrashError.fileRecovered(recoveryURL)
            }
            throw error
        }
        guard quarantinedIdentity == identity else {
            guard let recoveryURL = Self.restoreOrRecover(from: quarantinedURL, to: url) else {
                throw FileTrashError.fileChanged
            }
            if recoveryURL != url {
                throw FileTrashError.fileRecovered(recoveryURL)
            }
            throw FileTrashError.fileChanged
        }

        do {
            try trashOperation(quarantinedURL)
        } catch {
            if let recoveryURL = Self.restoreOrRecover(from: quarantinedURL, to: url), recoveryURL != url {
                throw FileTrashError.fileRecovered(recoveryURL)
            }
            throw error
        }
    }

    private static func renameExclusively(from sourceURL: URL, to destinationURL: URL) -> Int32 {
        sourceURL.withUnsafeFileSystemRepresentation { sourcePath in
            guard let sourcePath else {
                errno = EINVAL
                return -1
            }
            return destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                guard let destinationPath else {
                    errno = EINVAL
                    return -1
                }
                return Darwin.renamex_np(sourcePath, destinationPath, UInt32(RENAME_EXCL))
            }
        }
    }

    private static func restoreOrRecover(from quarantinedURL: URL, to originalURL: URL) -> URL? {
        if renameExclusively(from: quarantinedURL, to: originalURL) == 0 {
            return originalURL
        }

        let directoryURL = originalURL.deletingLastPathComponent()
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let pathExtension = originalURL.pathExtension
        for _ in 0..<100 {
            var candidateURL = directoryURL.appendingPathComponent(
                "CaptureStudio Recovered - \(baseName) \(UUID().uuidString)"
            )
            if !pathExtension.isEmpty {
                candidateURL.appendPathExtension(pathExtension)
            }
            if renameExclusively(from: quarantinedURL, to: candidateURL) == 0 {
                return candidateURL
            }
            guard errno == EEXIST else {
                return nil
            }
        }
        return nil
    }

    private static func removeDirectoryIfStillOwned(_ url: URL, identity: CaptureFileIdentity) {
        guard identity.matchesExistingFile(at: url) else {
            return
        }
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return
            }
            _ = Darwin.rmdir(path)
        }
    }

    private static func posixError(_ value: Int32) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: value) ?? .EIO)
    }
}

@MainActor
public protocol CaptureWindowVisibilityControlling {
    func hideCaptureWindows()
    func hideCaptureWindows(excluding excludedWindow: NSWindow?)
    func restoreCaptureWindows()
}

public extension CaptureWindowVisibilityControlling {
    func hideCaptureWindows(excluding excludedWindow: NSWindow?) {
        hideCaptureWindows()
    }
}

@MainActor
public final class AppKitCaptureWindowVisibilityController: CaptureWindowVisibilityControlling {
    private var hiddenWindows: [NSWindow] = []
    private var isCaptureWindowSuppressionActive = false
    private let windowProvider: @MainActor () -> [NSWindow]

    public convenience init() {
        self.init(windowProvider: { NSApp?.windows ?? [] })
    }

    init(windowProvider: @escaping @MainActor () -> [NSWindow]) {
        self.windowProvider = windowProvider
    }

    public func hideCaptureWindows() {
        isCaptureWindowSuppressionActive = true
        hideVisibleCaptureWindows(excluding: nil)
    }

    public func hideCaptureWindows(excluding excludedWindow: NSWindow?) {
        guard isCaptureWindowSuppressionActive else {
            return
        }

        hideVisibleCaptureWindows(excluding: excludedWindow)
    }

    private func hideVisibleCaptureWindows(excluding excludedWindow: NSWindow?) {
        let windowsToHide = windowProvider().filter { window in
            window !== excludedWindow
                && window.isVisible
                && !(window is NSPanel)
                && window.styleMask.rawValue != NSWindow.StyleMask.borderless.rawValue
        }

        for window in windowsToHide {
            if !hiddenWindows.contains(where: { $0 === window }) {
                hiddenWindows.append(window)
            }
            window.orderOut(nil)
        }
    }

    public func restoreCaptureWindows() {
        hiddenWindows.forEach { window in
            window.makeKeyAndOrderFront(nil)
        }
        hiddenWindows.removeAll()
        isCaptureWindowSuppressionActive = false
    }
}
