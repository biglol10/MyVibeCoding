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
        var directoriesToVisit = [rootURL.standardizedFileURL]
        var visitedDirectories = Set<URL>()

        while !directoriesToVisit.isEmpty {
            try Task.checkCancellation()
            let directoryURL = directoriesToVisit.removeFirst().standardizedFileURL
            guard visitedDirectories.insert(directoryURL).inserted else {
                continue
            }

            let entries = try await fileSystemService.contentsOfDirectory(at: directoryURL, options: options)
            matches.append(contentsOf: FileEntrySearchFilter.filtered(entries, criteria: criteria))

            directoriesToVisit.append(contentsOf: entries.compactMap { entry in
                entry.isDirectoryLike ? entry.url.standardizedFileURL : nil
            })
        }

        return SortEngine.sorted(matches, descriptor: EntrySortDescriptor(key: .path))
    }
}
