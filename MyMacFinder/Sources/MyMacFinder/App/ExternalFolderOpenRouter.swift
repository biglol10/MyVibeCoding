import Foundation

public enum ExternalFolderOpenError: Error, LocalizedError, Equatable, Sendable {
    case notFileURL
    case missing(String)
    case notDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .notFileURL:
            return "MyMacFinder can only open local folder URLs."
        case .missing(let path):
            return "The requested folder is no longer available: \(path)"
        case .notDirectory(let path):
            return "The requested path is not a folder: \(path)"
        }
    }
}

public struct ExternalFolderOpenRouter {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func validate(_ url: URL) throws -> URL {
        guard url.isFileURL else {
            throw ExternalFolderOpenError.notFileURL
        }
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            throw ExternalFolderOpenError.missing(standardized.path)
        }
        guard isDirectory.boolValue else {
            throw ExternalFolderOpenError.notDirectory(standardized.path)
        }
        return standardized
    }
}
