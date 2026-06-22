import Foundation

public struct ProcessSampler {
    public init() {}

    public func sample(limit: Int? = nil) throws -> [ProcessMetric] {
        let output = try ProcessCommand.run("/bin/ps", arguments: ["-axo", "pid=,pcpu=,rss=,comm="])
        let processes = output
            .split(whereSeparator: \.isNewline)
            .compactMap(parseLine)

        let sorted = ProcessSorting.filtered(processes, searchText: "", sortKey: .cpu)
        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    private func parseLine(_ line: Substring) -> ProcessMetric? {
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4,
              let pid = Int32(parts[0]),
              let cpu = Double(parts[1]),
              let rssKB = UInt64(parts[2])
        else {
            return nil
        }

        let path = String(parts[3])
        let name = URL(fileURLWithPath: path).lastPathComponent.isEmpty
            ? path
            : URL(fileURLWithPath: path).lastPathComponent
        return ProcessMetric(
            pid: pid,
            name: name,
            cpuPercent: cpu,
            memoryBytes: rssKB * 1_024,
            path: path,
            bundleIdentifier: Bundle(path: path)?.bundleIdentifier
        )
    }
}
