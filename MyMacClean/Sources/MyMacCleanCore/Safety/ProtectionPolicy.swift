import Foundation

public struct ProtectionPolicy: Sendable {
    private let allowedUserLibraryAppDataRoots: [URL]
    private let protectedRoots: [URL]

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.allowedUserLibraryAppDataRoots = [
            homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Preferences", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Saved Application State", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Containers", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Group Containers", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Logs", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/HTTPStorages", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/WebKit", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Application Scripts", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        ]
        self.protectedRoots = [
            homeDirectory.appendingPathComponent("Desktop", isDirectory: true),
            homeDirectory.appendingPathComponent("Documents", isDirectory: true),
            homeDirectory.appendingPathComponent("Downloads", isDirectory: true),
            homeDirectory.appendingPathComponent("Pictures", isDirectory: true),
            homeDirectory.appendingPathComponent("Movies", isDirectory: true),
            homeDirectory.appendingPathComponent("Music", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Mobile Documents", isDirectory: true),
            URL(fileURLWithPath: "/System", isDirectory: true),
            URL(fileURLWithPath: "/bin", isDirectory: true),
            URL(fileURLWithPath: "/sbin", isDirectory: true),
            URL(fileURLWithPath: "/usr", isDirectory: true),
            URL(fileURLWithPath: "/private", isDirectory: true),
            URL(fileURLWithPath: "/var", isDirectory: true)
        ]
    }

    public func isProtected(_ url: URL) -> Bool {
        if allowedUserLibraryAppDataRoots.contains(where: { PathUtilities.isDescendant(url, of: $0) }) {
            return false
        }
        return protectedRoots.contains { PathUtilities.isDescendant(url, of: $0) }
    }
}
