import Foundation
import Darwin
import UniformTypeIdentifiers

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
            for entry in FileEntrySearchFilter.filtered(entries, criteria: criteria) {
                try Task.checkCancellation()
                if let content = criteria.advanced?.content.trimmingCharacters(in: .whitespacesAndNewlines),
                   !content.isEmpty {
                    guard try Self.matchesContent(entry, query: content) else { continue }
                }
                matches.append(entry)
            }

            directoriesToVisit.append(contentsOf: entries.compactMap { entry in
                guard criteria.includeSubfolders, entry.isDirectoryLike,
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
    // Read only regular local text files, without following symlinks or allocating without a limit.
    // Unsupported/binary/large files are excluded; document contents are never uploaded.
    static let contentByteLimit = 10 * 1024 * 1024
    static func matchesContent(_ entry: FileEntry, query: String) throws -> Bool {
        guard !entry.isDirectoryLike, !entry.isArchiveBacked, entry.kind != .symlink else { return false }
        // A decodable PDF or office container is not a text document. Never match its raw internals.
        let ext = entry.fileExtension.lowercased()
        let textExtensions: Set<String> = ["txt", "md", "markdown", "csv", "tsv", "log", "json", "jsonl", "yaml", "yml", "toml", "xml", "html", "htm", "css", "js", "jsx", "ts", "tsx", "swift", "py", "rb", "go", "rs", "c", "h", "cpp", "hpp", "java", "kt", "sh", "sql", "ini", "conf"]
        guard ext.isEmpty || textExtensions.contains(ext) || UTType(filenameExtension: ext)?.conforms(to: .plainText) == true else { return false }
        let fd = Darwin.open(entry.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size <= contentByteLimit else { return false }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 { return false }
            if count == 0 { break }
            guard data.count + count <= contentByteLimit else { return false }
            data.append(contentsOf: buffer.prefix(count))
        }
        let text: String?
        guard !data.starts(with: Array("%PDF-".utf8)), !data.starts(with: [0x50, 0x4b, 0x03, 0x04]),
              !data.starts(with: [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]) else { return false }
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
            text = String(data: data, encoding: .utf16)
        } else {
            guard !data.contains(0) else { return false }
            text = String(data: data, encoding: .utf8)
        }
        try Task.checkCancellation()
        return text?.precomposedStringWithCanonicalMapping.range(
            of: query.precomposedStringWithCanonicalMapping,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

}
