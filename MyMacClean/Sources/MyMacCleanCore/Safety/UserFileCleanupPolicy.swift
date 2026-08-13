import Foundation

public struct UserFileCleanupPolicy: Sendable {
    private struct AllowedRoot: Sendable {
        let lexical: URL
        let resolved: URL
    }

    private let allowedRoots: [AllowedRoot]

    public init(allowedRoots: [URL]) {
        self.allowedRoots = allowedRoots
            .filter(Self.accepts(root:))
            .map {
                AllowedRoot(
                    lexical: $0.standardizedFileURL,
                    resolved: $0.resolvingSymlinksInPath().standardizedFileURL
                )
            }
    }

    public static func accepts(root: URL) -> Bool {
        let path = root.resolvingSymlinksInPath().standardizedFileURL.path
        let rejectedRoots: Set<String> = [
            "/", "/Users", "/Applications", "/Library", "/System",
            "/bin", "/sbin", "/usr", "/private", "/var", "/Volumes"
        ]
        guard !rejectedRoots.contains(path) else { return false }

        let rejectedTrees = ["/Applications", "/Library", "/System", "/bin", "/sbin", "/usr"]
        guard !rejectedTrees.contains(where: { path.hasPrefix($0 + "/") }) else { return false }

        let components = path.split(separator: "/")
        if components.count == 2,
           (components.first == "Users" || components.first == "Volumes") {
            return false
        }
        return true
    }

    public func isProtected(_ url: URL) -> Bool {
        let lexicalURL = url.standardizedFileURL
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard !isSystemPath(lexicalURL), !isSystemPath(resolvedURL) else { return true }
        return !allowedRoots.contains { root in
            let isLexicallyInside = PathUtilities.isDescendant(lexicalURL, of: root.lexical)
                || PathUtilities.isDescendant(lexicalURL, of: root.resolved)
            return isLexicallyInside && PathUtilities.isDescendant(resolvedURL, of: root.resolved)
        }
    }

    public var deletionProtectionPolicy: DeletionProtectionPolicy {
        DeletionProtectionPolicy { url in
            isProtected(url)
        }
    }

    private func isSystemPath(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let blockedRoots = ["/Applications", "/Library", "/System", "/bin", "/sbin", "/usr"]
        if blockedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return true
        }

        let temporaryRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        if path == temporaryRoot || path.hasPrefix(temporaryRoot + "/") {
            return false
        }
        return path == "/private"
            || path.hasPrefix("/private/")
            || path == "/var"
            || path.hasPrefix("/var/")
    }
}
