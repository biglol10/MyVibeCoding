import Foundation

public enum FileDropValidator {
    public static func validate(
        urls: [URL],
        destinationFolder: URL,
        operation: DropOperation,
        fileManager: FileManager = .default
    ) throws {
        guard !urls.isEmpty else {
            throw ExplorerError.invalidPath("No dropped files.")
        }

        let destination = destinationFolder.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExplorerError.notDirectory(destination.path)
        }

        for source in urls.map(\.standardizedFileURL) {
            if source == destination {
                throw ExplorerError.readFailed("Cannot drop an item onto itself.")
            }

            if isDescendant(destination, of: source) {
                let verb = operation == .copy ? "copy" : "move"
                throw ExplorerError.readFailed("Cannot \(verb) a folder into itself.")
            }
        }
    }

    private static func isDescendant(_ possibleChild: URL, of possibleParent: URL) -> Bool {
        let childPath = possibleChild.standardizedFileURL.path
        let parentPath = possibleParent.standardizedFileURL.path
        guard childPath != parentPath else {
            return false
        }
        return childPath.hasPrefix(parentPath + "/")
    }
}
