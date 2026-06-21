import Foundation

public enum PathUtilities {
    public static func standardizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    public static func isDescendant(_ child: URL, of parent: URL) -> Bool {
        let childPath = standardizedPath(child)
        let parentPath = standardizedPath(parent)
        return childPath == parentPath || childPath.hasPrefix(parentPath.hasSuffix("/") ? parentPath : parentPath + "/")
    }
}
