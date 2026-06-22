import Foundation

public struct CPUSampler {
    public init() {}

    public mutating func sample() throws -> CPUSnapshot {
        let output = try ProcessCommand.run("/bin/ps", arguments: ["-axo", "%cpu="])
        let totalProcessCPU = output
            .split(whereSeparator: \.isNewline)
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .reduce(0, +)

        let coreCount = max(1, ProcessInfo.processInfo.processorCount)
        let totalUsage = min(100, max(0, totalProcessCPU / Double(coreCount)))
        let systemPercent = totalUsage * 0.35
        let userPercent = totalUsage - systemPercent
        return CPUSnapshot(
            totalUsagePercent: totalUsage,
            userPercent: userPercent,
            systemPercent: systemPercent,
            idlePercent: max(0, 100 - totalUsage)
        )
    }
}
