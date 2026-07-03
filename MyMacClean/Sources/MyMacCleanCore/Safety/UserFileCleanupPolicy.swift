import Foundation

public struct UserFileCleanupPolicy: Sendable {
    private let allowedRoots: [URL]

    public init(allowedRoots: [URL]) {
        self.allowedRoots = allowedRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
    }

    public func isProtected(_ url: URL) -> Bool {
        let normalizedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard !isSystemPath(normalizedURL) else { return true }
        return !allowedRoots.contains { root in
            PathUtilities.isDescendant(normalizedURL, of: root)
                || PathUtilities.isDescendantResolvingSymlinks(normalizedURL, of: root)
        }
    }

    public var deletionProtectionPolicy: DeletionProtectionPolicy {
        DeletionProtectionPolicy { url in
            isProtected(url)
        }
    }

    private func isSystemPath(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path == "/System"
            || path.hasPrefix("/System/")
            || path == "/bin"
            || path.hasPrefix("/bin/")
            || path == "/sbin"
            || path.hasPrefix("/sbin/")
            || path == "/usr"
            || path.hasPrefix("/usr/")
    }
}
