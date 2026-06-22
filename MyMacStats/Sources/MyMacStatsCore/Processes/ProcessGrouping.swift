import Foundation

public struct ProcessAppGroup: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let processes: [ProcessMetric]

    public init(id: String, name: String, cpuPercent: Double, memoryBytes: UInt64, processes: [ProcessMetric]) {
        self.id = id
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.processes = processes
    }
}

public enum ProcessGrouping {
    public static func groups(
        _ processes: [ProcessMetric],
        searchText: String,
        sortKey: ProcessSortKey,
        ascending: Bool = false
    ) -> [ProcessAppGroup] {
        let grouped = Dictionary(grouping: processes, by: groupIdentity(for:))
        let appGroups = grouped.map { identity, groupProcesses in
            let sortedProcesses = ProcessSorting.filtered(
                groupProcesses,
                searchText: "",
                sortKey: sortKey,
                ascending: ascending
            )
            return ProcessAppGroup(
                id: identity.id,
                name: identity.name,
                cpuPercent: groupProcesses.reduce(0) { $0 + $1.cpuPercent },
                memoryBytes: groupProcesses.reduce(0) { $0 + $1.memoryBytes },
                processes: sortedProcesses
            )
        }

        let filteredGroups = filter(appGroups, searchText: searchText)
        return filteredGroups.sorted { lhs, rhs in
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
                orderedBefore = nameOrder == .orderedSame ? lhs.id < rhs.id : nameOrder == .orderedAscending
            case .pid:
                orderedBefore = minimumPID(lhs) < minimumPID(rhs)
            }
            return ascending ? orderedBefore : !orderedBefore
        }
    }

    private static func filter(_ groups: [ProcessAppGroup], searchText: String) -> [ProcessAppGroup] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return groups }
        return groups.filter { group in
            group.name.localizedCaseInsensitiveContains(trimmedSearch)
                || group.processes.contains { process in
                    process.name.localizedCaseInsensitiveContains(trimmedSearch)
                        || String(process.pid).contains(trimmedSearch)
                        || (process.path?.localizedCaseInsensitiveContains(trimmedSearch) ?? false)
                        || (process.bundleIdentifier?.localizedCaseInsensitiveContains(trimmedSearch) ?? false)
                }
        }
    }

    private static func minimumPID(_ group: ProcessAppGroup) -> Int32 {
        group.processes.map(\.pid).min() ?? 0
    }

    private static func groupIdentity(for process: ProcessMetric) -> ProcessGroupIdentity {
        if let appName = owningApplicationName(from: process.path) {
            return ProcessGroupIdentity(id: "app:\(appName.localizedLowercase)", name: appName)
        }
        if let bundleIdentifier = process.bundleIdentifier, !bundleIdentifier.isEmpty {
            return ProcessGroupIdentity(id: "bundle:\(bundleIdentifier)", name: normalizedName(process.name))
        }
        let name = normalizedName(process.name)
        return ProcessGroupIdentity(id: "name:\(name.localizedLowercase)", name: name)
    }

    private static func owningApplicationName(from path: String?) -> String? {
        guard let path else { return nil }
        let components = URL(fileURLWithPath: path).pathComponents
        guard let appComponent = components.first(where: { $0.hasSuffix(".app") }) else { return nil }
        return String(appComponent.dropLast(4))
    }

    private static func normalizedName(_ name: String) -> String {
        name
            .replacingOccurrences(of: " Helper", with: "")
            .replacingOccurrences(of: " \\([^)]*\\)", with: "", options: .regularExpression)
    }
}

private struct ProcessGroupIdentity: Hashable {
    let id: String
    let name: String
}
