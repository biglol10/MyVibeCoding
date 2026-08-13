import Foundation

public struct FileSizeCalculator: Sendable {
    private let sizeProvider: @Sendable (URL, Bool) throws -> Int64

    public init() {
        self.sizeProvider = Self.defaultSizeOfItem
    }

    public init(sizeProvider: @escaping @Sendable (URL, Bool) throws -> Int64) {
        self.sizeProvider = sizeProvider
    }

    public func sizeOfItem(at url: URL, recursive: Bool = true) throws -> Int64 {
        try sizeProvider(url, recursive)
    }

    private static func defaultSizeOfItem(at url: URL, recursive: Bool) throws -> Int64 {
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
        if resourceValues.isDirectory == true && recursive {
            return try defaultDirectorySize(at: url)
        }
        return Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileSize ?? 0)
    }

    private static func defaultDirectorySize(at url: URL) throws -> Int64 {
        var traversalError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                traversalError = error
                return false
            }
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey])
            if values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }
        }
        if let traversalError {
            throw traversalError
        }
        return total
    }
}
