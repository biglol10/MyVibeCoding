import Foundation

public enum IndexingDecision: Equatable, Sendable {
    case exclude
    case indexOnly
    case indexAndDescend
}

public struct IndexingPolicy: Equatable, Sendable {
    private static let excludedDirectoryNames: Set<String> = [
        ".git", ".build", "node_modules", "DerivedData"
    ]

    public let homePath: String
    public let includeHidden: Bool
    public let userExcludedPaths: Set<String>

    public init(
        homePath: String,
        includeHidden: Bool,
        userExcludedPaths: Set<String> = []
    ) {
        self.homePath = URL(fileURLWithPath: homePath).standardizedFileURL.path
        self.includeHidden = includeHidden
        self.userExcludedPaths = Set(
            userExcludedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        )
    }

    public func decision(for metadata: FileMetadata) -> IndexingDecision {
        let path = URL(fileURLWithPath: metadata.path).standardizedFileURL.path
        let protectedPaths = [
            "/System",
            "/Library",
            URL(fileURLWithPath: homePath).appendingPathComponent("Library/Caches").path
        ]

        if protectedPaths.contains(where: { Self.isSameOrDescendant(path, of: $0) })
            || userExcludedPaths.contains(where: { Self.isSameOrDescendant(path, of: $0) }) {
            return .exclude
        }

        if metadata.isDirectory && Self.excludedDirectoryNames.contains(metadata.name) {
            return .exclude
        }

        if !includeHidden && (metadata.isHidden || metadata.name.hasPrefix(".")) {
            return .exclude
        }

        if metadata.isSymlink || metadata.isPackage {
            return .indexOnly
        }
        return metadata.isDirectory ? .indexAndDescend : .indexOnly
    }

    private static func isSameOrDescendant(_ path: String, of ancestor: String) -> Bool {
        let normalizedAncestor = URL(fileURLWithPath: ancestor).standardizedFileURL.path
        return path == normalizedAncestor || path.hasPrefix(normalizedAncestor + "/")
    }
}
