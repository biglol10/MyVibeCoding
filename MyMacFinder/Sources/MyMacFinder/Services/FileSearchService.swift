import Foundation

public protocol FileSearchServicing: Sendable {
    func search(
        in rootURL: URL,
        criteria: FileEntrySearchCriteria,
        options: DirectoryReadOptions
    ) async throws -> [FileEntry]
}

public struct FileSearchService: FileSearchServicing, Sendable {
    private let fileSystemService: any FileSystemServicing

    public init(fileSystemService: any FileSystemServicing = FileSystemService()) {
        self.fileSystemService = fileSystemService
    }

    public func search(
        in rootURL: URL,
        criteria: FileEntrySearchCriteria,
        options: DirectoryReadOptions = DirectoryReadOptions()
    ) async throws -> [FileEntry] {
        var matches: [FileEntry] = []
        let rootURL = rootURL.standardizedFileURL
        var directoriesToVisit = [rootURL]
        var visitedDirectories = Set<URL>()
        var cursor = 0

        while cursor < directoriesToVisit.count {
            try Task.checkCancellation()
            let directoryURL = directoriesToVisit[cursor].standardizedFileURL
            cursor += 1
            guard visitedDirectories.insert(directoryURL).inserted else {
                continue
            }

            let entries: [FileEntry]
            do {
                entries = try await fileSystemService.contentsOfDirectory(at: directoryURL, options: options)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ExplorerError {
                if directoryURL != rootURL, case .permissionDenied = error {
                    continue
                }
                throw error
            }
            try Task.checkCancellation()
            matches.append(contentsOf: FileEntrySearchFilter.filtered(entries, criteria: criteria))

            directoriesToVisit.append(contentsOf: entries.compactMap { entry in
                guard entry.isDirectoryLike,
                      entry.isReadable,
                      entry.kind != .symlink else {
                    return nil
                }
                return entry.url.standardizedFileURL
            })
        }

        try Task.checkCancellation()
        return SortEngine.sorted(matches, descriptor: EntrySortDescriptor(key: .path))
    }
}
