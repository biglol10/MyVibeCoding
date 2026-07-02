import Foundation

public enum PathUtilities {
    public static func standardizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    public static func resolvedStandardizedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public static func isDescendant(_ child: URL, of parent: URL) -> Bool {
        let childPath = standardizedPath(child)
        let parentPath = standardizedPath(parent)
        return path(childPath, isDescendantOf: parentPath)
    }

    public static func isDescendantResolvingSymlinks(_ child: URL, of parent: URL) -> Bool {
        let childPath = resolvedStandardizedPath(child)
        let parentPath = resolvedStandardizedPath(parent)
        return path(childPath, isDescendantOf: parentPath)
    }

    private static func path(_ childPath: String, isDescendantOf parentPath: String) -> Bool {
        return childPath == parentPath || childPath.hasPrefix(parentPath.hasSuffix("/") ? parentPath : parentPath + "/")
    }
}
