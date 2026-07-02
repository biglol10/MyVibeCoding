import Darwin
import Foundation

struct CPUTicks: Equatable, Sendable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64

    var total: UInt64 {
        user + system + idle
    }

    func delta(from previous: CPUTicks?) -> CPUTicks {
        guard let previous,
              user >= previous.user,
              system >= previous.system,
              idle >= previous.idle
        else {
            return self
        }
        return CPUTicks(
            user: user - previous.user,
            system: system - previous.system,
            idle: idle - previous.idle
        )
    }
}

public struct CPUSampler {
    private var previousTicks: CPUTicks?

    public init() {}

    public mutating func sample() throws -> CPUSnapshot {
        let currentTicks = try Self.readProcessorTicks()
        let snapshot = Self.snapshot(previous: previousTicks, current: currentTicks)
        previousTicks = currentTicks
        return snapshot
    }

    static func snapshot(previous: CPUTicks?, current: CPUTicks, sampledAt: Date = Date()) -> CPUSnapshot {
        let delta = current.delta(from: previous)
        guard delta.total > 0 else {
            return CPUSnapshot(
                totalUsagePercent: 0,
                userPercent: 0,
                systemPercent: 0,
                idlePercent: 100,
                sampledAt: sampledAt
            )
        }

        let total = Double(delta.total)
        let userPercent = clampPercent(Double(delta.user) / total * 100)
        let systemPercent = clampPercent(Double(delta.system) / total * 100)
        let idlePercent = clampPercent(Double(delta.idle) / total * 100)

        return CPUSnapshot(
            totalUsagePercent: clampPercent(userPercent + systemPercent),
            userPercent: userPercent,
            systemPercent: systemPercent,
            idlePercent: idlePercent,
            sampledAt: sampledAt
        )
    }

    private static func readProcessorTicks() throws -> CPUTicks {
        var processorCount: natural_t = 0
        var processorInfoCount: mach_msg_type_number_t = 0
        var processorInfo: processor_info_array_t?
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        let result = host_processor_info(
            host,
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )
        guard result == KERN_SUCCESS, let processorInfo else {
            throw SamplerError.systemCallFailed("host_processor_info")
        }
        defer {
            let byteCount = vm_size_t(Int(processorInfoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: processorInfo)), byteCount)
        }

        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        let statesPerCPU = Int(CPU_STATE_MAX)

        for cpuIndex in 0..<Int(processorCount) {
            let base = cpuIndex * statesPerCPU
            user += tickValue(processorInfo[base + Int(CPU_STATE_USER)])
            user += tickValue(processorInfo[base + Int(CPU_STATE_NICE)])
            system += tickValue(processorInfo[base + Int(CPU_STATE_SYSTEM)])
            idle += tickValue(processorInfo[base + Int(CPU_STATE_IDLE)])
        }

        return CPUTicks(user: user, system: system, idle: idle)
    }

    private static func tickValue(_ value: integer_t) -> UInt64 {
        UInt64(UInt32(bitPattern: value))
    }

    private static func clampPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}
