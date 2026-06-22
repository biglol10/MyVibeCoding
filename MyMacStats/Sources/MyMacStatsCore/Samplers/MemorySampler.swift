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
        let free = UInt64(stats.free_count) * pageBytes
        let compressed = UInt64(stats.compressor_page_count) * pageBytes
        let cached = UInt64(stats.inactive_count + stats.speculative_count) * pageBytes
        let used = total > free ? total - free : 0

        return MemorySnapshot(
            totalBytes: total,
            usedBytes: used,
            freeBytes: free,
            compressedBytes: compressed,
            cachedBytes: cached,
            swapUsedBytes: nil,
            pressure: .unavailable
        )
    }
}
