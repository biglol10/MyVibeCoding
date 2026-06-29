import Foundation

public struct MountedVolume: Identifiable, Hashable, Codable, Sendable {
    public let id: URL
    public let url: URL
    public let name: String
    public let isLocal: Bool
    public let isRemovable: Bool
    public let isBrowsable: Bool
    public let isReadable: Bool

    public init(
        url: URL,
        name: String? = nil,
        isLocal: Bool = true,
        isRemovable: Bool = false,
        isBrowsable: Bool = true,
        isReadable: Bool = true
    ) {
        let standardizedURL = url.standardizedFileURL
        self.id = standardizedURL
        self.url = standardizedURL
        self.name = name ?? ""
        self.isLocal = isLocal
        self.isRemovable = isRemovable
        self.isBrowsable = isBrowsable
        self.isReadable = isReadable
    }

    public var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        let lastPathComponent = url.lastPathComponent
        if !lastPathComponent.isEmpty {
            return lastPathComponent
        }

        return url.path
    }

    public var systemImageName: String {
        if !isLocal {
            return "network"
        }
        if isRemovable {
            return "externaldrive"
        }
        return "internaldrive"
    }

    public static func sortedForSidebar(_ volumes: [MountedVolume]) -> [MountedVolume] {
        volumes.sorted { lhs, rhs in
            let lhsGroup = sidebarGroupOrder(lhs)
            let rhsGroup = sidebarGroupOrder(rhs)
            if lhsGroup != rhsGroup {
                return lhsGroup < rhsGroup
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func sidebarGroupOrder(_ volume: MountedVolume) -> Int {
        if !volume.isLocal {
            return 0
        }
        if volume.isRemovable {
            return 1
        }
        return 2
    }
}
