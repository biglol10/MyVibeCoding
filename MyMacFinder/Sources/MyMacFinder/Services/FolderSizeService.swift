import Foundation

public protocol FolderSizeCalculating: Sendable {
    func size(of folder: URL) throws -> Int64
}

public struct FolderSizeService: FolderSizeCalculating, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func size(of folder: URL) throws -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExplorerError.notDirectory(folder.path)
        }

        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw ExplorerError.permissionDenied(folder.path)
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        if let enumerationError {
            throw ExplorerError.operationFailed("Folder size could not be fully calculated: \(enumerationError.localizedDescription)")
        }
        return total
    }
}
