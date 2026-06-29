import Foundation

enum ArchivePathSafety {
    static func isSafeEntryPath(_ rawPath: String) -> Bool {
        let path = rawPath.replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty, !path.hasPrefix("/") else {
            return false
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty else {
            return false
        }

        guard components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            return false
        }

        if let first = components.first, first.hasSuffix(":") {
            return false
        }

        return true
    }

    static func validateEntryPath(_ rawPath: String) throws {
        guard isSafeEntryPath(rawPath) else {
            throw ExplorerError.readFailed("ZIP entry attempted to extract outside destination: \(rawPath)")
        }
    }
}
