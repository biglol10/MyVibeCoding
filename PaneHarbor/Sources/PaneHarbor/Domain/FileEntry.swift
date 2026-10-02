import Foundation

public enum FileEntryKind: String, Codable, CaseIterable, Sendable {
    case folder
    case file
    case symlink
    case package
    case volume
    case zipVirtualFolder
    case zipVirtualFile
    case other
}

public struct FileEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: URL
    public let url: URL
    public let name: String
    public let kind: FileEntryKind
    public let typeDescription: String
    public let fileExtension: String
    public let size: Int64?
    public let dateModified: Date?
    public let dateCreated: Date?
    public let dateAccessed: Date?
    public let isHidden: Bool
    public let isDirectoryLike: Bool
    public let isReadable: Bool
    public let finderTags: [FinderTag]
    public let source: FileEntrySource

    public init(
        url: URL,
        name: String,
        kind: FileEntryKind,
        typeDescription: String,
        fileExtension: String,
        size: Int64?,
        dateModified: Date?,
        dateCreated: Date?,
        dateAccessed: Date?,
        isHidden: Bool,
        isDirectoryLike: Bool,
        isReadable: Bool,
        finderTags: [FinderTag] = [],
        source: FileEntrySource = .fileSystem
    ) {
        self.id = url
        self.url = url
        self.name = name
        self.kind = kind
        self.typeDescription = typeDescription
        self.fileExtension = fileExtension
        self.size = size
        self.dateModified = dateModified
        self.dateCreated = dateCreated
        self.dateAccessed = dateAccessed
        self.isHidden = isHidden
        self.isDirectoryLike = isDirectoryLike
        self.isReadable = isReadable
        self.finderTags = FinderTag.normalized(finderTags.map(\.name))
        self.source = source
    }

    public var isArchiveBacked: Bool {
        if case .archive = source {
            return true
        }
        return false
    }

    public func replacingFinderTags(_ tags: [FinderTag]) -> FileEntry {
        FileEntry(
            url: url,
            name: name,
            kind: kind,
            typeDescription: typeDescription,
            fileExtension: fileExtension,
            size: size,
            dateModified: dateModified,
            dateCreated: dateCreated,
            dateAccessed: dateAccessed,
            isHidden: isHidden,
            isDirectoryLike: isDirectoryLike,
            isReadable: isReadable,
            finderTags: tags,
            source: source
        )
    }
}
