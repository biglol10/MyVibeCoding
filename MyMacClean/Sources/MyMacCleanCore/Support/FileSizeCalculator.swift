import Foundation

public struct FileSizeCalculator: Sendable {
    public init() {}

    public func sizeOfItem(at url: URL, recursive: Bool = true) throws -> Int64 {
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
        if resourceValues.isDirectory == true && recursive {
            return try directorySize(at: url)
        }
        return Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileSize ?? 0)
    }

    private func directorySize(at url: URL) throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey])
            if values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }
        }
        return total
    }
}
