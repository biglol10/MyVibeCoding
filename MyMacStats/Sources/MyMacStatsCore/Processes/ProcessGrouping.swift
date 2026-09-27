import Foundation

public struct ProcessAppGroup: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let processes: [ProcessMetric]

    public var isApplicationTarget: Bool { id.hasPrefix("app:") }

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
            switch sortKey {
            case .cpu:
                if lhs.cpuPercent != rhs.cpuPercent {
                    return ascending ? lhs.cpuPercent < rhs.cpuPercent : lhs.cpuPercent > rhs.cpuPercent
                }
                return orderedByNameThenID(lhs, rhs)
            case .memory:
                if lhs.memoryBytes != rhs.memoryBytes {
                    return ascending ? lhs.memoryBytes < rhs.memoryBytes : lhs.memoryBytes > rhs.memoryBytes
                }
                return orderedByNameThenID(lhs, rhs)
            case .name:
                let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameOrder != .orderedSame {
                    return ascending ? nameOrder == .orderedAscending : nameOrder == .orderedDescending
                }
                return lhs.id < rhs.id
            case .pid:
                let lhsPID = minimumPID(lhs)
                let rhsPID = minimumPID(rhs)
                if lhsPID != rhsPID {
                    return ascending ? lhsPID < rhsPID : lhsPID > rhsPID
                }
                return lhs.id < rhs.id
            }
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

    private static func orderedByNameThenID(_ lhs: ProcessAppGroup, _ rhs: ProcessAppGroup) -> Bool {
        let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private static func groupIdentity(for process: ProcessMetric) -> ProcessGroupIdentity {
        if let application = owningApplication(from: process.path) {
            return application
        }
        // A shared executable name or bundle ID does not prove shared ownership.
        return ProcessGroupIdentity(id: "pid:\(process.pid)", name: process.name)
    }

    private static func owningApplication(from path: String?) -> ProcessGroupIdentity? {
        guard let path, path.hasPrefix("/") else { return nil }
        // This runs while rendering live rows. Normalize lexically: URL construction
        // can probe the filesystem for each executable and stall the main thread.
        var components: [Substring] = []
        for component in path.split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                if !components.isEmpty { components.removeLast() }
            } else {
                components.append(component)
            }
        }
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let appPath = "/" + components[...index].joined(separator: "/")
        return ProcessGroupIdentity(id: "app:\(appPath)", name: String(components[index].dropLast(4)))
    }
}

private struct ProcessGroupIdentity: Hashable {
    let id: String
    let name: String
}
