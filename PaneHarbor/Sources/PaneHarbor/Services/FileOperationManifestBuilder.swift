import Foundation

public struct FileOperationManifest: Equatable, Sendable {
    public var roots: [URL]
    public var totalFileCount: Int
    public var totalByteCount: Int64
}

public struct FileOperationManifestBuilder: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func manifest(for urls: [URL]) throws -> FileOperationManifest {
        var totalFileCount = 0
        var totalByteCount: Int64 = 0

        for url in urls.map(\.standardizedFileURL) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw ExplorerError.pathDoesNotExist(url.path)
            }

            if isDirectory.boolValue {
                let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsPackageDescendants]
                )
                while let child = enumerator?.nextObject() as? URL {
                    let values = try child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    if values.isRegularFile == true {
                        totalFileCount += 1
                        totalByteCount += Int64(values.fileSize ?? 0)
                    }
                }
            } else {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                totalFileCount += 1
                totalByteCount += Int64(values.fileSize ?? 0)
            }
        }

        return FileOperationManifest(
            roots: urls.map(\.standardizedFileURL),
            totalFileCount: totalFileCount,
            totalByteCount: totalByteCount
        )
    }
}
