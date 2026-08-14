import Foundation
import SQLite3

public actor SQLiteIndexReader {
    private let databaseURL: URL

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        let connection = try SQLiteConnection(
            path: databaseURL.path,
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        )
        let statement = try connection.prepare("SELECT 1 FROM entries LIMIT 1")
        _ = try statement.step()
    }

    public func search(
        query: SearchQuery,
        limit: Int = 200,
        after cursor: SearchCursor? = nil
    ) throws -> SearchPage {
        let boundedLimit = min(max(limit, 1), 500)
        let connection = try SQLiteConnection(
            path: databaseURL.path,
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        )
        let built = Self.buildSearch(query: query, cursor: cursor, limit: boundedLimit)
        let statement = try connection.prepare(built.sql)
        try statement.bind(built.bindings)

        var entries: [IndexedEntry] = []
        var ranks: [Double] = []
        while try statement.step() == SQLITE_ROW {
            guard let kind = IndexedFileKind(rawValue: try statement.text(at: 8)) else {
                throw SQLiteIndexError.invalidData("Unknown kind in entry row")
            }
            let device = statement.optionalInt64(at: 15).map { UInt64(bitPattern: $0) }
            let inode = statement.optionalInt64(at: 16).map { UInt64(bitPattern: $0) }
            entries.append(
                IndexedEntry(
                    id: statement.int64(at: 0),
                    scopeID: try statement.text(at: 1),
                    path: try statement.text(at: 2),
                    parentPath: try statement.text(at: 3),
                    name: try statement.text(at: 4),
                    searchName: try statement.text(at: 5),
                    searchPath: try statement.text(at: 6),
                    fileExtension: try statement.text(at: 7),
                    kind: kind,
                    sizeBytes: statement.int64(at: 9),
                    modifiedAt: Date(timeIntervalSince1970: statement.double(at: 10)),
                    isDirectory: statement.int64(at: 11) == 1,
                    isSymlink: statement.int64(at: 12) == 1,
                    isPackage: statement.int64(at: 13) == 1,
                    isHidden: statement.int64(at: 14) == 1,
                    deviceID: device,
                    inode: inode,
                    scanGeneration: statement.int64(at: 17)
                )
            )
            ranks.append(statement.double(at: 18))
        }

        let nextCursor: SearchCursor?
        if entries.count == boundedLimit, let last = entries.last, let rank = ranks.last {
            nextCursor = SearchCursor(rank: rank, modifiedAt: last.modifiedAt, entryID: last.id)
        } else {
            nextCursor = nil
        }
        return SearchPage(entries: entries, nextCursor: nextCursor)
    }

    private static func buildSearch(
        query: SearchQuery,
        cursor: SearchCursor?,
        limit: Int
    ) -> (sql: String, bindings: [SQLiteBindValue]) {
        let primaryTerm = query.nameTerms.first ?? query.freeTerms.first
        let rankExpression: String
        var innerBindings: [SQLiteBindValue] = []
        if let primaryTerm {
            rankExpression = """
            CASE
              WHEN e.search_name = ? THEN 0.0
              WHEN e.search_name LIKE ? ESCAPE '\\' THEN 1.0
              WHEN e.search_name LIKE ? ESCAPE '\\' THEN 2.0
              ELSE 3.0
            END
            """
            let escaped = escapeLike(primaryTerm)
            innerBindings.append(contentsOf: [
                .text(primaryTerm),
                .text("\(escaped)%"),
                .text("%\(escaped)%")
            ])
        } else {
            rankExpression = "3.0"
        }

        var ftsTerms: [String] = []
        var predicates: [String] = []

        for term in query.freeTerms {
            if term.count >= 3 {
                ftsTerms.append(quoteFTS(term))
            } else {
                predicates.append("e.search_name LIKE ? ESCAPE '\\'")
                innerBindings.append(.text("\(escapeLike(term))%"))
            }
        }
        for term in query.nameTerms {
            if term.count >= 3 {
                ftsTerms.append("search_name:\(quoteFTS(term))")
            } else {
                predicates.append("e.search_name LIKE ? ESCAPE '\\'")
                innerBindings.append(.text("\(escapeLike(term))%"))
            }
        }
        for term in query.pathTerms {
            if term.count >= 3 {
                ftsTerms.append("search_path:\(quoteFTS(term))")
            } else {
                predicates.append("e.search_path LIKE ? ESCAPE '\\'")
                innerBindings.append(.text("%\(escapeLike(term))%"))
            }
        }

        let joins: String
        if ftsTerms.isEmpty {
            joins = ""
        } else {
            joins = "JOIN entries_fts ON entries_fts.rowid = e.id"
            predicates.append("entries_fts MATCH ?")
            innerBindings.append(.text(ftsTerms.joined(separator: " AND ")))
        }

        if !query.extensions.isEmpty {
            predicates.append("e.extension IN (\(placeholders(query.extensions.count)))")
            innerBindings.append(contentsOf: query.extensions.map(SQLiteBindValue.text))
        }
        if !query.kinds.isEmpty {
            predicates.append("e.kind IN (\(placeholders(query.kinds.count)))")
            innerBindings.append(contentsOf: query.kinds.map { .text($0.rawValue) })
        }
        if let range = query.modifiedRange {
            predicates.append("e.modified_at >= ? AND e.modified_at < ?")
            innerBindings.append(.double(range.lowerBound.timeIntervalSince1970))
            innerBindings.append(.double(range.upperBound.timeIntervalSince1970))
        }

        let filterSQL = predicates.isEmpty ? "" : "WHERE " + predicates.joined(separator: " AND ")
        var outerPredicates: [String] = []
        var outerBindings: [SQLiteBindValue] = []
        if let cursor {
            outerPredicates.append(
                """
                (relevance_rank > ?
                  OR (relevance_rank = ? AND modified_at < ?)
                  OR (relevance_rank = ? AND modified_at = ? AND id > ?))
                """
            )
            outerBindings.append(contentsOf: [
                .double(cursor.rank),
                .double(cursor.rank),
                .double(cursor.modifiedAt.timeIntervalSince1970),
                .double(cursor.rank),
                .double(cursor.modifiedAt.timeIntervalSince1970),
                .int64(cursor.entryID)
            ])
        }

        let outerFilter = outerPredicates.isEmpty ? "" : "WHERE " + outerPredicates.joined(separator: " AND ")
        let sql = """
        SELECT * FROM (
          SELECT
            e.id, e.scope_id, e.path, e.parent_path, e.name, e.search_name, e.search_path,
            e.extension, e.kind, e.size_bytes, e.modified_at, e.is_directory, e.is_symlink,
            e.is_package, e.is_hidden, e.device_id, e.inode, e.scan_generation,
            \(rankExpression) AS relevance_rank
          FROM entries e
          \(joins)
          \(filterSQL)
        ) ranked
        \(outerFilter)
        ORDER BY relevance_rank ASC, modified_at DESC, id ASC
        LIMIT ?
        """
        return (sql, innerBindings + outerBindings + [.int64(Int64(limit))])
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static func quoteFTS(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
