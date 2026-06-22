import Foundation

public struct DiskSampler {
    private let path: String

    public init(path: String = "/") {
        self.path = path
    }

    public func sample() throws -> DiskSnapshot {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: path)
        guard let total = attributes[.systemSize] as? NSNumber,
              let free = attributes[.systemFreeSize] as? NSNumber
        else {
            throw SamplerError.invalidOutput("File system attributes missing size values")
        }

        let url = URL(fileURLWithPath: path)
        let resourceValues = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey])
        return DiskSnapshot(
            volumeName: resourceValues?.volumeLocalizedName ?? "Macintosh HD",
            mountPoint: path,
            totalBytes: total.uint64Value,
            freeBytes: free.uint64Value,
            readBytesPerSecond: nil,
            writeBytesPerSecond: nil
        )
    }
}
