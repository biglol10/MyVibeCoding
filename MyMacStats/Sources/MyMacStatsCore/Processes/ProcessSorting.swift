import Foundation

public enum ProcessSorting {
    public static func filtered(
        _ processes: [ProcessMetric],
        searchText: String,
        sortKey: ProcessSortKey,
        ascending: Bool = false
    ) -> [ProcessMetric] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredProcesses: [ProcessMetric]
        if trimmedSearch.isEmpty {
            filteredProcesses = processes
        } else {
            filteredProcesses = processes.filter {
                $0.name.localizedCaseInsensitiveContains(trimmedSearch)
                    || String($0.pid).contains(trimmedSearch)
                    || ($0.path?.localizedCaseInsensitiveContains(trimmedSearch) ?? false)
                    || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(trimmedSearch) ?? false)
            }
        }

        return filteredProcesses.sorted { lhs, rhs in
            switch sortKey {
            case .cpu:
                if lhs.cpuPercent != rhs.cpuPercent {
                    return ascending ? lhs.cpuPercent < rhs.cpuPercent : lhs.cpuPercent > rhs.cpuPercent
                }
                return orderedByNameThenPID(lhs, rhs)
            case .memory:
                if lhs.memoryBytes != rhs.memoryBytes {
                    return ascending ? lhs.memoryBytes < rhs.memoryBytes : lhs.memoryBytes > rhs.memoryBytes
                }
                return orderedByNameThenPID(lhs, rhs)
            case .name:
                let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameOrder != .orderedSame {
                    return ascending ? nameOrder == .orderedAscending : nameOrder == .orderedDescending
                }
                return lhs.pid < rhs.pid
            case .pid:
                guard lhs.pid != rhs.pid else { return false }
                return ascending ? lhs.pid < rhs.pid : lhs.pid > rhs.pid
            }
        }
    }

    private static func orderedByNameThenPID(_ lhs: ProcessMetric, _ rhs: ProcessMetric) -> Bool {
        let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.pid < rhs.pid
    }
}
