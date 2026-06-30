import Darwin
import Foundation

public struct MemorySampler {
    public init() {}

    public func sample() throws -> MemorySnapshot {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()

        let result = withUnsafeMutablePointer(to: &stats) { statsPointer in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                host_statistics64(host, HOST_VM_INFO64, pointer, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw SamplerError.systemCallFailed("host_statistics64")
        }

        var pageSize = vm_size_t()
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else {
            throw SamplerError.systemCallFailed("host_page_size")
        }

        let total = ProcessInfo.processInfo.physicalMemory
        let pageBytes = UInt64(pageSize)

        return Self.snapshot(
            totalBytes: total,
            pageBytes: pageBytes,
            freePages: UInt64(stats.free_count),
            inactivePages: UInt64(stats.inactive_count),
            speculativePages: UInt64(stats.speculative_count),
            compressorPages: UInt64(stats.compressor_page_count)
        )
    }

    static func snapshot(
        totalBytes: UInt64,
        pageBytes: UInt64,
        freePages: UInt64,
        inactivePages: UInt64,
        speculativePages: UInt64,
        compressorPages: UInt64
    ) -> MemorySnapshot {
        let free = freePages * pageBytes
        let compressed = compressorPages * pageBytes
        let cached = (inactivePages + speculativePages) * pageBytes
        let unavailable = free + cached
        let used = totalBytes > unavailable ? totalBytes - unavailable : 0

        return MemorySnapshot(
            totalBytes: totalBytes,
            usedBytes: used,
            freeBytes: free,
            compressedBytes: compressed,
            cachedBytes: cached,
            swapUsedBytes: nil,
            pressure: .unavailable
        )
    }
}
