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
            compressorPages: UInt64(stats.compressor_page_count),
            swapUsedBytes: Self.readSwapUsedBytes(),
            pressure: Self.readMemoryPressure()
        )
    }

    static func snapshot(
        totalBytes: UInt64,
        pageBytes: UInt64,
        freePages: UInt64,
        inactivePages: UInt64,
        speculativePages: UInt64,
        compressorPages: UInt64,
        swapUsedBytes: UInt64? = nil,
        pressure: MemoryPressure = .normal
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
            swapUsedBytes: swapUsedBytes,
            pressure: pressure
        )
    }

    static func pressure(fromRawValue rawValue: Int32) -> MemoryPressure {
        switch rawValue {
        case ..<0:
            .unavailable
        case 0:
            .normal
        case 1:
            .warning
        default:
            .critical
        }
    }

    private static func readMemoryPressure() -> MemoryPressure {
        var rawValue: Int32 = -1
        var size = MemoryLayout<Int32>.stride
        guard sysctlbyname("vm.memory_pressure", &rawValue, &size, nil, 0) == 0 else {
            return .unavailable
        }
        return pressure(fromRawValue: rawValue)
    }

    private static func readSwapUsedBytes() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            return nil
        }
        return usage.xsu_used
    }
}
