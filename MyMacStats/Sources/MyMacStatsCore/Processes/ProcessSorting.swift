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
            let orderedBefore: Bool
            switch sortKey {
            case .cpu:
                orderedBefore = lhs.cpuPercent == rhs.cpuPercent
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhs.cpuPercent < rhs.cpuPercent
            case .memory:
                orderedBefore = lhs.memoryBytes == rhs.memoryBytes
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhs.memoryBytes < rhs.memoryBytes
            case .name:
                let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                orderedBefore = nameOrder == .orderedSame ? lhs.pid < rhs.pid : nameOrder == .orderedAscending
            case .pid:
                orderedBefore = lhs.pid < rhs.pid
            }
            return ascending ? orderedBefore : !orderedBefore
        }
    }
}
