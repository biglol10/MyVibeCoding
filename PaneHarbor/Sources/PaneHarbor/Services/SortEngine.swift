import Foundation

public struct EntryGroup: Equatable, Sendable {
    public let title: String
    public let entries: [FileEntry]
}

public enum SortEngine {
    public static func sorted(_ entries: [FileEntry], descriptor: EntrySortDescriptor) -> [FileEntry] {
        entries.sorted { lhs, rhs in
            if let folderComparison = compareFolderFile(lhs, rhs, ordering: descriptor.folderFileOrdering) {
                return folderComparison
            }

            let comparison = compare(lhs, rhs, key: descriptor.key)
            if comparison == .orderedSame {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

            switch descriptor.direction {
            case .ascending:
                return comparison == .orderedAscending
            case .descending:
                return comparison == .orderedDescending
            }
        }
    }

    public static func group(_ entries: [FileEntry], descriptor: EntryGroupDescriptor) -> [EntryGroup] {
        let dictionary = Dictionary(grouping: entries) { entry in
            groupTitle(for: entry, key: descriptor.key)
        }

        return dictionary.keys.sorted().map { key in
            EntryGroup(title: key, entries: dictionary[key] ?? [])
        }
    }

    private static func compareFolderFile(_ lhs: FileEntry, _ rhs: FileEntry, ordering: FolderFileOrdering) -> Bool? {
        guard lhs.isDirectoryLike != rhs.isDirectoryLike else {
            return nil
        }

        switch ordering {
        case .foldersFirst:
            return lhs.isDirectoryLike
        case .filesFirst:
            return !lhs.isDirectoryLike
        case .mixed:
            return nil
        }
    }

    private static func compare(_ lhs: FileEntry, _ rhs: FileEntry, key: SortKey) -> ComparisonResult {
        switch key {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name)
        case .size:
            return compareOptional(lhs.size, rhs.size)
        case .kind:
            return lhs.typeDescription.localizedStandardCompare(rhs.typeDescription)
        case .fileExtension:
            return lhs.fileExtension.localizedStandardCompare(rhs.fileExtension)
        case .dateModified:
            return compareOptional(lhs.dateModified, rhs.dateModified)
        case .dateCreated:
            return compareOptional(lhs.dateCreated, rhs.dateCreated)
        case .dateAccessed:
            return compareOptional(lhs.dateAccessed, rhs.dateAccessed)
        case .permissions, .owner:
            return .orderedSame
        case .hidden:
            return String(lhs.isHidden).compare(String(rhs.isHidden))
        case .folderFileType:
            return lhs.kind.rawValue.compare(rhs.kind.rawValue)
        case .path:
            return lhs.url.path.localizedStandardCompare(rhs.url.path)
        }
    }

    private static func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs < rhs { return .orderedAscending }
            if lhs > rhs { return .orderedDescending }
            return .orderedSame
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        }
    }

    private static func groupTitle(for entry: FileEntry, key: GroupKey) -> String {
        switch key {
        case .folderFile:
            return entry.isDirectoryLike ? "Folders" : "Files"
        case .kind:
            return entry.typeDescription
        case .fileExtension:
            return entry.fileExtension.isEmpty ? "No Extension" : ".\(entry.fileExtension)"
        case .dateBucket:
            return dateBucket(for: entry.dateModified)
        case .sizeBucket:
            return sizeBucket(for: entry.size)
        case .hidden:
            return entry.isHidden ? "Hidden" : "Visible"
        case .source:
            return entry.kind == .zipVirtualFile || entry.kind == .zipVirtualFolder ? "ZIP" : "Filesystem"
        }
    }

    private static func dateBucket(for date: Date?) -> String {
        guard let date else { return "No Date" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        if let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()), date >= sevenDaysAgo {
            return "Previous 7 Days"
        }
        return "Older"
    }

    private static func sizeBucket(for size: Int64?) -> String {
        guard let size else { return "No Size" }
        if size < 1_000_000 { return "Small" }
        if size < 100_000_000 { return "Medium" }
        return "Large"
    }
}
