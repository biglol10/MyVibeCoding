import Foundation
import IOKit

public struct DiskIOCounters: Equatable, Sendable {
    public let bytesRead: UInt64
    public let bytesWritten: UInt64

    public init(bytesRead: UInt64, bytesWritten: UInt64) {
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
    }
}

public final class DiskSampler {
    private let path: String
    private let fileSystemAttributesProvider: (String) throws -> [FileAttributeKey: Any]
    private let volumeNameProvider: (URL) -> String?
    private let ioCounterProvider: () -> DiskIOCounters?
    private let dateProvider: () -> Date
    private var previousIOCounterSample: DiskIOCounterSample?

    public convenience init(path: String = "/") {
        self.init(
            path: path,
            fileSystemAttributesProvider: FileManager.default.attributesOfFileSystem(forPath:),
            volumeNameProvider: Self.volumeName(for:),
            ioCounterProvider: Self.systemIOCounters,
            dateProvider: { Date() }
        )
    }

    init(
        path: String,
        fileSystemAttributesProvider: @escaping (String) throws -> [FileAttributeKey: Any],
        volumeNameProvider: @escaping (URL) -> String?,
        ioCounterProvider: @escaping () -> DiskIOCounters?,
        dateProvider: @escaping () -> Date
    ) {
        self.path = path
        self.fileSystemAttributesProvider = fileSystemAttributesProvider
        self.volumeNameProvider = volumeNameProvider
        self.ioCounterProvider = ioCounterProvider
        self.dateProvider = dateProvider
    }

    public func sample() throws -> DiskSnapshot {
        let attributes = try fileSystemAttributesProvider(path)
        guard let total = attributes[.systemSize] as? NSNumber,
              let free = attributes[.systemFreeSize] as? NSNumber
        else {
            throw SamplerError.invalidOutput("File system attributes missing size values")
        }

        let url = URL(fileURLWithPath: path)
        let speeds = currentIOSpeeds()
        return DiskSnapshot(
            volumeName: volumeNameProvider(url) ?? Self.fallbackVolumeName(for: url),
            mountPoint: path,
            totalBytes: total.uint64Value,
            freeBytes: free.uint64Value,
            readBytesPerSecond: speeds?.readBytesPerSecond,
            writeBytesPerSecond: speeds?.writeBytesPerSecond
        )
    }

    private func currentIOSpeeds() -> (readBytesPerSecond: UInt64, writeBytesPerSecond: UInt64)? {
        guard let counters = ioCounterProvider() else {
            previousIOCounterSample = nil
            return nil
        }
        let now = dateProvider()
        defer {
            previousIOCounterSample = DiskIOCounterSample(counters: counters, date: now)
        }

        guard let previousIOCounterSample else { return nil }
        let elapsed = now.timeIntervalSince(previousIOCounterSample.date)
        guard elapsed > 0,
              counters.bytesRead >= previousIOCounterSample.counters.bytesRead,
              counters.bytesWritten >= previousIOCounterSample.counters.bytesWritten
        else {
            return nil
        }

        let readDelta = counters.bytesRead - previousIOCounterSample.counters.bytesRead
        let writeDelta = counters.bytesWritten - previousIOCounterSample.counters.bytesWritten
        return (
            readBytesPerSecond: UInt64(Double(readDelta) / elapsed),
            writeBytesPerSecond: UInt64(Double(writeDelta) / elapsed)
        )
    }

    private static func volumeName(for url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeNameKey])
        return values?.volumeLocalizedName ?? values?.volumeName
    }

    private static func fallbackVolumeName(for url: URL) -> String {
        let lastPathComponent = url.standardizedFileURL.lastPathComponent
        if !lastPathComponent.isEmpty {
            return lastPathComponent
        }
        return url.path == "/" ? "Root Volume" : url.path
    }

    private static func systemIOCounters() -> DiskIOCounters? {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var bytesRead: UInt64 = 0
        var bytesWritten: UInt64 = 0
        var foundCounters = false

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as NSDictionary?,
                  let statistics = dictionary["Statistics"] as? NSDictionary
            else {
                continue
            }

            guard let read = uint64Value(statistics["Bytes (Read)"]),
                  let written = uint64Value(statistics["Bytes (Write)"])
            else {
                continue
            }

            bytesRead += read
            bytesWritten += written
            foundCounters = true
        }

        guard foundCounters else { return nil }
        return DiskIOCounters(bytesRead: bytesRead, bytesWritten: bytesWritten)
    }

    private static func uint64Value(_ value: Any?) -> UInt64? {
        switch value {
        case let number as NSNumber:
            return number.uint64Value
        case let value as UInt64:
            return value
        case let value as UInt:
            return UInt64(value)
        case let value as Int where value >= 0:
            return UInt64(value)
        default:
            return nil
        }
    }
}

private struct DiskIOCounterSample {
    let counters: DiskIOCounters
    let date: Date
}
