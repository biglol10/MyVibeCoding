import Foundation

public struct ProtectionPolicy: Sendable {
    private let allowedUserApplicationRoots: [URL]
    private let allowedUserLibraryAppDataRoots: [URL]
    private let allowedTemporaryRoots: [URL]
    private let protectedUserRoots: [URL]
    private let additionalProtectedRoots: [URL]

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        additionalProtectedRoots: [URL] = []
    ) {
        self.allowedUserApplicationRoots = [
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
        self.allowedTemporaryRoots = [
            FileManager.default.temporaryDirectory
        ]
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
        self.additionalProtectedRoots = ProtectionPolicy.defaultAdditionalProtectedRoots() + additionalProtectedRoots
        self.protectedUserRoots = [
            homeDirectory.appendingPathComponent("Desktop", isDirectory: true),
            homeDirectory.appendingPathComponent("Documents", isDirectory: true),
            homeDirectory.appendingPathComponent("Downloads", isDirectory: true),
            homeDirectory.appendingPathComponent("Pictures", isDirectory: true),
            homeDirectory.appendingPathComponent("Movies", isDirectory: true),
            homeDirectory.appendingPathComponent("Music", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Mobile Documents", isDirectory: true)
        ]
    }

    public func isProtected(_ url: URL) -> Bool {
        if isProtectedByAdditionalRoots(url) {
            return true
        }
        if resolvesIntoProtectedUserRoot(url) {
            return true
        }
        if isAllowedUserDataPath(url) {
            return false
        }
        if isAllowedApplicationBundle(url) {
            return false
        }
        return true
    }

    private func isAllowedUserDataPath(_ url: URL) -> Bool {
        allowedRoots.contains {
            let resolvedRoot = $0.resolvingSymlinksInPath().standardizedFileURL
            let isLexicallyInside = PathUtilities.isDescendant(url, of: $0)
                || PathUtilities.isDescendant(url, of: resolvedRoot)
            return isLexicallyInside && PathUtilities.isDescendantResolvingSymlinks(url, of: $0)
        }
    }

    private func isAllowedApplicationBundle(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "app" else { return false }
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        return ([systemApplications] + allowedUserApplicationRoots).contains { root in
            let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
            let isLexicallyInside = PathUtilities.isDescendant(url, of: root)
                || PathUtilities.isDescendant(url, of: resolvedRoot)
            return isLexicallyInside && PathUtilities.isDescendantResolvingSymlinks(url, of: root)
        }
    }

    private func isProtectedByAdditionalRoots(_ url: URL) -> Bool {
        additionalProtectedRoots.contains {
            PathUtilities.isDescendant(url, of: $0) || PathUtilities.isDescendantResolvingSymlinks(url, of: $0)
        }
    }

    private func resolvesIntoProtectedUserRoot(_ url: URL) -> Bool {
        protectedUserRoots.contains { PathUtilities.isDescendantResolvingSymlinks(url, of: $0) }
    }

    private var allowedRoots: [URL] {
        allowedUserApplicationRoots + allowedUserLibraryAppDataRoots + allowedTemporaryRoots
    }

    private static func defaultAdditionalProtectedRoots() -> [URL] {
        [Bundle.main.bundleURL]
    }
}
