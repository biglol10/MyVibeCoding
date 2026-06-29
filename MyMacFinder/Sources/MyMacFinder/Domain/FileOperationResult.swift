import Foundation

public struct FileMoveRecord: Equatable, Sendable {
    public var source: URL
    public var destination: URL

    public init(source: URL, destination: URL) {
        self.source = source.standardizedFileURL
        self.destination = destination.standardizedFileURL
    }
}

public struct FileTrashRecord: Equatable, Sendable {
    public var original: URL
    public var trashed: URL

    public init(original: URL, trashed: URL) {
        self.original = original.standardizedFileURL
        self.trashed = trashed.standardizedFileURL
    }
}

public struct FileOperationResult: Equatable, Sendable {
    public var createdURLs: [URL]
    public var movedItems: [FileMoveRecord]
    public var renamedItem: FileMoveRecord?
    public var trashedItems: [FileTrashRecord]
    public var replacedItems: [FileTrashRecord]
    public var skippedURLs: [URL]

    public init(
        createdURLs: [URL] = [],
        movedItems: [FileMoveRecord] = [],
        renamedItem: FileMoveRecord? = nil,
        trashedItems: [FileTrashRecord] = [],
        replacedItems: [FileTrashRecord] = [],
        skippedURLs: [URL] = []
    ) {
        self.createdURLs = createdURLs.map(\.standardizedFileURL)
        self.movedItems = movedItems
        self.renamedItem = renamedItem
        self.trashedItems = trashedItems
        self.replacedItems = replacedItems
        self.skippedURLs = skippedURLs.map(\.standardizedFileURL)
    }

    public var changedFileSystem: Bool {
        !createdURLs.isEmpty ||
            !movedItems.isEmpty ||
            renamedItem != nil ||
            !trashedItems.isEmpty ||
            !replacedItems.isEmpty
    }
}
