import Foundation

public enum FileEntrySearchFilter {
    public static func filtered(_ entries: [FileEntry], query: String) -> [FileEntry] {
        filtered(entries, criteria: FileEntrySearchCriteria(query: query))
    }

    public static func filtered(_ entries: [FileEntry], criteria: FileEntrySearchCriteria) -> [FileEntry] {
        let terms = queryTerms(criteria.query)

        return entries.filter { entry in
            matches(entry, criteria: criteria, terms: terms)
        }
    }

    private static func matches(_ entry: FileEntry, criteria: FileEntrySearchCriteria, terms: [String]) -> Bool {
        guard matchesKind(entry, kind: criteria.kind) else {
            return false
        }
        guard criteria.fileExtension.isEmpty || entry.fileExtension == criteria.fileExtension else {
            return false
        }
        guard matchesTagQuery(entry, tagQuery: criteria.finderTagQuery) else {
            return false
        }
        guard !terms.isEmpty else {
            return true
        }

        return terms.allSatisfy { term in
            matches(entry, term: term)
        }
    }

    private static func matchesKind(_ entry: FileEntry, kind: SearchKindFilter) -> Bool {
        switch kind {
        case .any:
            return true
        case .files:
            return !entry.isDirectoryLike
        case .folders:
            return entry.isDirectoryLike
        }
    }

    private static func queryTerms(_ query: String) -> [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func matches(_ entry: FileEntry, term: String) -> Bool {
        searchableFields(for: entry).contains { field in
            field.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private static func matchesTagQuery(_ entry: FileEntry, tagQuery: String) -> Bool {
        let terms = queryTerms(tagQuery)
        guard !terms.isEmpty else {
            return true
        }

        let tagNames = entry.finderTags.map(\.name)
        return terms.allSatisfy { term in
            tagNames.contains { tagName in
                tagName.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    private static func searchableFields(for entry: FileEntry) -> [String] {
        [
            entry.name,
            entry.fileExtension,
            entry.typeDescription,
            entry.url.lastPathComponent
        ] + entry.finderTags.map(\.name)
    }
}
