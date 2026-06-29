import Foundation

public struct PaneID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum SortKey: String, Codable, CaseIterable, Sendable {
    case name
    case size
    case kind
    case fileExtension
    case dateModified
    case dateCreated
    case dateAccessed
    case permissions
    case owner
    case hidden
    case folderFileType
    case path

    public static var userSelectableCases: [SortKey] {
        [
            .name,
            .size,
            .kind,
            .fileExtension,
            .dateModified,
            .dateCreated,
            .dateAccessed,
            .hidden,
            .folderFileType,
            .path
        ]
    }

    public var title: String {
        switch self {
        case .name: return "Name"
        case .size: return "Size"
        case .kind: return "Kind"
        case .fileExtension: return "Extension"
        case .dateModified: return "Date Modified"
        case .dateCreated: return "Date Created"
        case .dateAccessed: return "Date Accessed"
        case .permissions: return "Permissions"
        case .owner: return "Owner"
        case .hidden: return "Hidden"
        case .folderFileType: return "Folder/File Type"
        case .path: return "Path"
        }
    }
}

public enum SortDirection: String, Codable, CaseIterable, Sendable {
    case ascending
    case descending

    public var title: String {
        switch self {
        case .ascending:
            return "Ascending"
        case .descending:
            return "Descending"
        }
    }
}

public enum FolderFileOrdering: String, Codable, CaseIterable, Sendable {
    case foldersFirst
    case filesFirst
    case mixed

    public var title: String {
        switch self {
        case .foldersFirst:
            return "Folders First"
        case .filesFirst:
            return "Files First"
        case .mixed:
            return "Mixed"
        }
    }
}

public enum ExplorerPaneMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case single
    case dual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .single:
            return "Single Pane"
        case .dual:
            return "Dual Pane"
        }
    }
}

public enum ExplorerFocusTarget: Equatable, Sendable {
    case path
    case search
    case clear
}

public enum SearchScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case currentFolder
    case recursive

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .currentFolder:
            return "Current Folder"
        case .recursive:
            return "Subfolders"
        }
    }
}

public enum SearchKindFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case any
    case files
    case folders

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .any:
            return "Any"
        case .files:
            return "Files"
        case .folders:
            return "Folders"
        }
    }
}

public struct ExplorerSearchOptions: Codable, Equatable, Sendable {
    public var scope: SearchScope
    public var kind: SearchKindFilter
    public var fileExtension: String
    public var finderTagQuery: String

    public init(
        scope: SearchScope = .currentFolder,
        kind: SearchKindFilter = .any,
        fileExtension: String = "",
        finderTagQuery: String = ""
    ) {
        self.scope = scope
        self.kind = kind
        self.fileExtension = Self.normalizedExtension(fileExtension)
        self.finderTagQuery = Self.normalizedTagQuery(finderTagQuery)
    }

    public static func normalizedExtension(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    public static func normalizedTagQuery(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct FileEntrySearchCriteria: Equatable, Sendable {
    public var query: String
    public var kind: SearchKindFilter
    public var fileExtension: String
    public var finderTagQuery: String

    public init(
        query: String = "",
        kind: SearchKindFilter = .any,
        fileExtension: String = "",
        tagQuery: String = ""
    ) {
        self.query = query
        self.kind = kind
        self.fileExtension = ExplorerSearchOptions.normalizedExtension(fileExtension)
        self.finderTagQuery = ExplorerSearchOptions.normalizedTagQuery(tagQuery)
    }
}

public struct ExplorerTabID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct ExplorerTab: Identifiable, Sendable {
    public let id: ExplorerTabID
    public var panes: [PaneState]
    public var activePaneIndex: Int
    public var pathInput: String
    public var searchQuery: String
    public var searchOptions: ExplorerSearchOptions

    public init(
        id: ExplorerTabID = ExplorerTabID(),
        panes: [PaneState],
        activePaneIndex: Int = 0,
        pathInput: String? = nil,
        searchQuery: String = "",
        searchOptions: ExplorerSearchOptions = ExplorerSearchOptions()
    ) {
        self.id = id
        self.panes = panes
        self.activePaneIndex = activePaneIndex
        self.pathInput = pathInput ?? panes.first?.location.displayPath ?? ""
        self.searchQuery = searchQuery
        self.searchOptions = searchOptions
    }

    public var title: String {
        guard panes.indices.contains(activePaneIndex) else {
            return "Tab"
        }

        switch panes[activePaneIndex].location {
        case .fileSystem(let url):
            let name = url.lastPathComponent
            return name.isEmpty ? url.path : name
        case .archive(let location):
            guard !location.internalPath.isEmpty else {
                return location.archiveURL.lastPathComponent
            }
            let name = URL(fileURLWithPath: location.internalPath).lastPathComponent
            return name.isEmpty ? location.archiveURL.lastPathComponent : name
        }
    }
}

public struct EntrySortDescriptor: Codable, Equatable, Sendable {
    public var key: SortKey
    public var direction: SortDirection
    public var folderFileOrdering: FolderFileOrdering

    public init(
        key: SortKey = .name,
        direction: SortDirection = .ascending,
        folderFileOrdering: FolderFileOrdering = .foldersFirst
    ) {
        self.key = key
        self.direction = direction
        self.folderFileOrdering = folderFileOrdering
    }
}

public enum GroupKey: String, Codable, CaseIterable, Sendable {
    case folderFile
    case kind
    case fileExtension
    case dateBucket
    case sizeBucket
    case hidden
    case source
}

public struct EntryGroupDescriptor: Codable, Equatable, Sendable {
    public var key: GroupKey

    public init(key: GroupKey) {
        self.key = key
    }
}

public struct PaneState: Identifiable, Sendable {
    public let id: PaneID
    public var location: PaneLocation
    public var entries: [FileEntry]
    public var selectedURLs: Set<URL>
    public var backStack: [PaneLocation]
    public var forwardStack: [PaneLocation]
    public var sort: EntrySortDescriptor
    public var group: EntryGroupDescriptor?
    public var isLoading: Bool
    public var error: ExplorerError?

    public init(
        location: PaneLocation = .fileSystem(FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL),
        sort: EntrySortDescriptor = EntrySortDescriptor()
    ) {
        self.id = PaneID()
        self.location = location
        self.entries = []
        self.selectedURLs = []
        self.backStack = []
        self.forwardStack = []
        self.sort = sort
        self.group = nil
        self.isLoading = false
        self.error = nil
    }

    public init(
        currentURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        sort: EntrySortDescriptor = EntrySortDescriptor()
    ) {
        self.init(location: .fileSystem(currentURL.standardizedFileURL), sort: sort)
    }

    public var currentURL: URL {
        switch location {
        case .fileSystem(let url):
            return url
        case .archive(let archiveLocation):
            return archiveLocation.archiveURL
        }
    }

    public var selectedEntries: [FileEntry] {
        entries.filter { selectedURLs.contains($0.url) }
    }
}

public enum ExplorerError: LocalizedError, Equatable, Sendable {
    case invalidPath(String)
    case pathDoesNotExist(String)
    case notDirectory(String)
    case permissionDenied(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .pathDoesNotExist(let path):
            return "Path does not exist: \(path)"
        case .notDirectory(let path):
            return "Path is not a folder: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .readFailed(let message):
            return message
        }
    }
}
