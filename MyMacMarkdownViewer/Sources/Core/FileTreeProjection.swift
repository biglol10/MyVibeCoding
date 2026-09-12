import Foundation

public struct FileTreeRow: Identifiable, Equatable, Sendable {
    public let entry: FileEntry
    public let depth: Int
    public var id: String { entry.id }
}

public enum FileTreeProjection {
    /// A single list of visible rows gives the lazy layout one stable, fixed-height
    /// view per ID. Nested lazy stacks can repeatedly invalidate each other's size.
    public static func rows(roots: [FileEntry], children: [String: [FileEntry]], expanded: Set<String>) -> [FileTreeRow] {
        var result: [FileTreeRow] = []
        var pending = roots.reversed().map { FileTreeRow(entry: $0, depth: 0) }
        var visited: Set<String> = []
        while let row = pending.popLast() {
            guard visited.insert(row.id).inserted else { continue }
            result.append(row)
            if row.entry.isDirectory, expanded.contains(row.id) {
                for child in (children[row.id] ?? []).reversed() {
                    pending.append(FileTreeRow(entry: child, depth: row.depth + 1))
                }
            }
        }
        return result
    }
}
