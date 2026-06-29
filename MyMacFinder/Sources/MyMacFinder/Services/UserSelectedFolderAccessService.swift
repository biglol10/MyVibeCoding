import AppKit
import Foundation

public enum FolderAccessSelectionResult: Equatable, Sendable {
    case granted(FolderAccessGrant, ResolvedFolderAccess)
    case cancelled
}

public struct ResolvedFolderAccess: Equatable, Sendable {
    public var url: URL
    public var isStale: Bool
    public var didStartAccessing: Bool

    public init(url: URL, isStale: Bool, didStartAccessing: Bool) {
        self.url = url.standardizedFileURL
        self.isStale = isStale
        self.didStartAccessing = didStartAccessing
    }
}

public protocol FolderPicking: AnyObject, Sendable {
    @MainActor
    func chooseFolder(startingAt url: URL?) async -> URL?
}

public protocol BookmarkResolving: AnyObject, Sendable {
    func bookmarkData(for url: URL, sandboxed: Bool) throws -> Data
    func resolve(_ grant: FolderAccessGrant) throws -> ResolvedFolderAccess
    func startAccessing(_ url: URL, sandboxed: Bool) -> ResolvedFolderAccess
    func stopAccessing(_ access: ResolvedFolderAccess)
}

public protocol UserSelectedFolderAccessing: AnyObject, Sendable {
    func chooseFolder(startingAt url: URL?, sandboxed: Bool) async throws -> FolderAccessSelectionResult
    func resolve(_ grant: FolderAccessGrant) throws -> ResolvedFolderAccess
    func stopAccessing(_ access: ResolvedFolderAccess)
}

public final class UserSelectedFolderAccessService: UserSelectedFolderAccessing, @unchecked Sendable {
    private let picker: any FolderPicking
    private let bookmarkResolver: any BookmarkResolving

    public init(
        picker: any FolderPicking = AppKitFolderPicker(),
        bookmarkResolver: any BookmarkResolving = SecurityScopedBookmarkResolver()
    ) {
        self.picker = picker
        self.bookmarkResolver = bookmarkResolver
    }

    public func chooseFolder(startingAt url: URL?, sandboxed: Bool) async throws -> FolderAccessSelectionResult {
        guard let selectedURL = await picker.chooseFolder(startingAt: url)?.standardizedFileURL else {
            return .cancelled
        }
        let bookmarkData = try bookmarkResolver.bookmarkData(for: selectedURL, sandboxed: sandboxed)
        let grant = FolderAccessGrant(url: selectedURL, bookmarkData: bookmarkData)
        let access = bookmarkResolver.startAccessing(selectedURL, sandboxed: sandboxed)
        return .granted(grant, access)
    }

    public func resolve(_ grant: FolderAccessGrant) throws -> ResolvedFolderAccess {
        try bookmarkResolver.resolve(grant)
    }

    public func stopAccessing(_ access: ResolvedFolderAccess) {
        bookmarkResolver.stopAccessing(access)
    }
}

public final class AppKitFolderPicker: FolderPicking, @unchecked Sendable {
    public init() {}

    @MainActor
    public func chooseFolder(startingAt url: URL?) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = url
        panel.prompt = "Choose"
        panel.message = "Choose a folder to grant MyMacFinder access."
        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }
}

public final class SecurityScopedBookmarkResolver: BookmarkResolving, @unchecked Sendable {
    public init() {}

    public func bookmarkData(for url: URL, sandboxed: Bool) throws -> Data {
        guard sandboxed else {
            return Data()
        }
        return try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public func resolve(_ grant: FolderAccessGrant) throws -> ResolvedFolderAccess {
        guard !grant.bookmarkData.isEmpty else {
            return startAccessing(grant.url, sandboxed: false)
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: grant.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        let didStart = url.startAccessingSecurityScopedResource()
        return ResolvedFolderAccess(url: url, isStale: isStale, didStartAccessing: didStart)
    }

    public func startAccessing(_ url: URL, sandboxed: Bool) -> ResolvedFolderAccess {
        let standardizedURL = url.standardizedFileURL
        let didStart = sandboxed ? standardizedURL.startAccessingSecurityScopedResource() : false
        return ResolvedFolderAccess(url: standardizedURL, isStale: false, didStartAccessing: didStart)
    }

    public func stopAccessing(_ access: ResolvedFolderAccess) {
        guard access.didStartAccessing else {
            return
        }
        access.url.stopAccessingSecurityScopedResource()
    }
}
