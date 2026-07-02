import Foundation

public struct FilePathStatus: Equatable, Sendable {
    public var exists: Bool
    public var isDirectory: Bool
    public var isReadable: Bool

    public init(exists: Bool, isDirectory: Bool, isReadable: Bool) {
        self.exists = exists
        self.isDirectory = isDirectory
        self.isReadable = isReadable
    }
}

public protocol PathStatusChecking: Sendable {
    func status(for url: URL) async -> FilePathStatus
}

public struct FileManagerPathStatusChecker: PathStatusChecking, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func status(for url: URL) async -> FilePathStatus {
        let fileManager = fileManager
        let url = url.standardizedFileURL
        return await Task.detached(priority: .utility) {
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let isReadable = exists ? fileManager.isReadableFile(atPath: url.path) : false
            return FilePathStatus(
                exists: exists,
                isDirectory: isDirectory.boolValue,
                isReadable: isReadable
            )
        }.value
    }
}
