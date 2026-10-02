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

        let canonicalDestination = FileSystemPathIdentity.canonicalDirectory(destination)
        for source in urls.map(\.standardizedFileURL) {
            let canonicalSource = try FileSystemPathIdentity.canonicalExistingEntryPreservingLeaf(source)
            if canonicalSource == canonicalDestination {
                throw ExplorerError.operationFailed("Cannot drop an item onto itself.")
            }

            if FileSystemPathIdentity.isDescendant(canonicalDestination, of: canonicalSource) {
                let verb = operation == .copy ? "copy" : "move"
                throw ExplorerError.operationFailed("Cannot \(verb) a folder into itself.")
            }
        }
    }
}
