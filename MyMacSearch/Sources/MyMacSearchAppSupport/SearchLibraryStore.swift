import Foundation
import MyMacSearchCore

public protocol SearchLibraryStoring: AnyObject {
    func load() throws -> SearchLibrary
    func recordRecent(query: String, sort: SearchSort, usedAt: Date) throws
    func clearRecent() throws
    @discardableResult
    func save(name: String, query: String, sort: SearchSort, at date: Date) throws -> SavedSearch
    func rename(id: UUID, name: String) throws
    func replace(id: UUID, query: String, sort: SearchSort, at date: Date) throws
    func remove(id: UUID) throws
    func move(fromOffsets: IndexSet, toOffset: Int) throws
}

public final class SearchLibraryStore: SearchLibraryStoring {
    public let libraryURL: URL
    public let lastGoodURL: URL
    public private(set) var didRecoverLastGood = false

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        libraryURL = directoryURL.appendingPathComponent("SearchLibrary.json")
        lastGoodURL = directoryURL.appendingPathComponent("SearchLibrary.last-good.json")
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    public func load() throws -> SearchLibrary {
        didRecoverLastGood = false
        if !fileManager.fileExists(atPath: libraryURL.path),
           !fileManager.fileExists(atPath: lastGoodURL.path) {
            return SearchLibrary()
        }
        if let library = try? decoded(at: libraryURL) { return library }
        if let library = try? decoded(at: lastGoodURL) {
            didRecoverLastGood = true
            return library
        }
        throw SearchLibraryError.corruptLibrary
    }

    public func recordRecent(query: String, sort: SearchSort, usedAt: Date = Date()) throws {
        let normalized = Self.normalize(query)
        guard !normalized.isEmpty else { return }
        var library = try load()
        library.recent.removeAll { Self.normalize($0.query) == normalized }
        library.recent.insert(RecentSearch(query: normalized, sort: sort, lastUsedAt: usedAt), at: 0)
        if library.recent.count > 20 { library.recent.removeLast(library.recent.count - 20) }
        try write(library)
    }

    public func clearRecent() throws {
        var library = try load()
        library.recent.removeAll()
        try write(library)
    }

    @discardableResult
    public func save(
        name: String,
        query: String,
        sort: SearchSort,
        at date: Date = Date()
    ) throws -> SavedSearch {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = Self.normalize(query)
        guard !normalizedName.isEmpty else { throw SearchLibraryError.invalidName }
        guard !normalizedQuery.isEmpty else { throw SearchLibraryError.invalidQuery }
        let saved = SavedSearch(
            name: normalizedName,
            query: normalizedQuery,
            sort: sort,
            createdAt: date,
            lastUsedAt: date
        )
        var library = try load()
        library.saved.append(saved)
        try write(library)
        return saved
    }

    public func rename(id: UUID, name: String) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw SearchLibraryError.invalidName }
        var library = try load()
        guard let index = library.saved.firstIndex(where: { $0.id == id }) else {
            throw SearchLibraryError.missingSavedSearch
        }
        library.saved[index].name = normalizedName
        try write(library)
    }

    public func replace(id: UUID, query: String, sort: SearchSort, at date: Date = Date()) throws {
        let normalized = Self.normalize(query)
        guard !normalized.isEmpty else { throw SearchLibraryError.invalidQuery }
        var library = try load()
        guard let index = library.saved.firstIndex(where: { $0.id == id }) else {
            throw SearchLibraryError.missingSavedSearch
        }
        library.saved[index].query = normalized
        library.saved[index].sort = sort
        library.saved[index].lastUsedAt = date
        try write(library)
    }

    public func remove(id: UUID) throws {
        var library = try load()
        guard library.saved.contains(where: { $0.id == id }) else {
            throw SearchLibraryError.missingSavedSearch
        }
        library.saved.removeAll { $0.id == id }
        try write(library)
    }

    public func move(fromOffsets: IndexSet, toOffset: Int) throws {
        var library = try load()
        let validOffsets = fromOffsets.filter { library.saved.indices.contains($0) }
        guard !validOffsets.isEmpty else { return }
        let moving = validOffsets.sorted().map { library.saved[$0] }
        for index in validOffsets.sorted(by: >) { library.saved.remove(at: index) }
        let removedBefore = validOffsets.filter { $0 < toOffset }.count
        let destination = min(max(toOffset - removedBefore, 0), library.saved.count)
        library.saved.insert(contentsOf: moving, at: destination)
        try write(library)
    }

    private func write(_ library: SearchLibrary) throws {
        guard library.schemaVersion == SearchLibrary.currentSchemaVersion else {
            throw SearchLibraryError.unsupportedSchema(library.schemaVersion)
        }
        try fileManager.createDirectory(at: libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(library)
        _ = try validated(data)
        if let previous = try? Data(contentsOf: libraryURL), (try? validated(previous)) != nil {
            try previous.write(to: lastGoodURL, options: .atomic)
        }
        try data.write(to: libraryURL, options: .atomic)
        if !fileManager.fileExists(atPath: lastGoodURL.path) {
            try data.write(to: lastGoodURL, options: .atomic)
        }
        didRecoverLastGood = false
    }

    private func decoded(at url: URL) throws -> SearchLibrary {
        try validated(Data(contentsOf: url))
    }

    private func validated(_ data: Data) throws -> SearchLibrary {
        let library = try decoder.decode(SearchLibrary.self, from: data)
        guard library.schemaVersion == SearchLibrary.currentSchemaVersion else {
            throw SearchLibraryError.unsupportedSchema(library.schemaVersion)
        }
        return library
    }

    public static func normalize(_ query: String) -> String {
        var result = ""
        var quoted = false
        var pendingSpace = false
        for character in query.trimmingCharacters(in: .whitespacesAndNewlines) {
            if character == "\"" {
                if pendingSpace, !result.isEmpty { result.append(" ") }
                pendingSpace = false
                quoted.toggle()
                result.append(character)
            } else if character.isWhitespace, !quoted {
                pendingSpace = true
            } else {
                if pendingSpace, !result.isEmpty { result.append(" ") }
                pendingSpace = false
                result.append(character)
            }
        }
        return result
    }
}
