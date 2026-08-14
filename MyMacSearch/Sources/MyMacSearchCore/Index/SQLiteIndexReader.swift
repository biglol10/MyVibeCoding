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
        request: SearchRequest,
        limit: Int = 200,
        after cursor: SearchPageCursor? = nil
    ) throws -> SearchPage {
        let boundedLimit = min(max(limit, 1), 500)
        let connection = try SQLiteConnection(
            path: databaseURL.path,
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        )
        let built = Self.buildSearch(request: request, cursor: cursor, limit: boundedLimit)
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

        let nextCursor: SearchPageCursor?
        if entries.count == boundedLimit, let last = entries.last, let rank = ranks.last {
            nextCursor = Self.cursor(for: last, rank: rank, sort: request.sort)
        } else {
            nextCursor = nil
        }
        return SearchPage(entries: entries, nextCursor: nextCursor)
    }

    public func search(
        query: SearchQuery,
        limit: Int = 200,
        after cursor: SearchPageCursor? = nil
    ) throws -> SearchPage {
        try search(
            request: SearchRequest(query: query, sort: query.isEmpty ? .modifiedNewest : .relevance),
            limit: limit,
            after: cursor
        )
    }

    public nonisolated static func loadScopes(at databaseURL: URL) throws -> [IndexScope] {
        let connection = try SQLiteConnection(
            path: databaseURL.path,
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        )
        let statement = try connection.prepare(
            """
            SELECT id, root_path, volume_type, is_enabled, completed_generation, last_event_id
            FROM scopes
            ORDER BY root_path ASC
            """
        )
        var scopes: [IndexScope] = []
        while try statement.step() == SQLITE_ROW {
            guard let volumeType = IndexedVolumeType(rawValue: try statement.text(at: 2)) else {
                throw SQLiteIndexError.invalidData("Unknown volume type in scope row")
            }
            scopes.append(
                IndexScope(
                    id: try statement.text(at: 0),
                    rootPath: try statement.text(at: 1),
                    volumeType: volumeType,
                    isEnabled: statement.int64(at: 3) == 1,
                    completedGeneration: statement.int64(at: 4),
                    lastEventID: statement.optionalInt64(at: 5).map { UInt64(bitPattern: $0) }
                )
            )
        }
        return scopes
    }

    private static func buildSearch(
        request: SearchRequest,
        cursor: SearchPageCursor?,
        limit: Int
    ) -> (sql: String, bindings: [SQLiteBindValue]) {
        let query = request.query
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
        if let range = query.sizeRange {
            switch range {
            case .greaterThan(let bytes):
                predicates.append("e.size_bytes > ?")
                innerBindings.append(.int64(bytes))
            case .atLeast(let bytes):
                predicates.append("e.size_bytes >= ?")
                innerBindings.append(.int64(bytes))
            case .lessThan(let bytes):
                predicates.append("e.size_bytes < ?")
                innerBindings.append(.int64(bytes))
            case .atMost(let bytes):
                predicates.append("e.size_bytes <= ?")
                innerBindings.append(.int64(bytes))
            case .closed(let lower, let upper):
                predicates.append("e.size_bytes >= ? AND e.size_bytes <= ?")
                innerBindings.append(.int64(lower))
                innerBindings.append(.int64(upper))
            }
        }

        let filterSQL = predicates.isEmpty ? "" : "WHERE " + predicates.joined(separator: " AND ")
        let order = searchOrder(sort: request.sort, cursor: cursor)

        let outerFilter = order.predicate.map { "WHERE \($0)" } ?? ""
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
        ORDER BY \(order.orderBy)
        LIMIT ?
        """
        return (sql, innerBindings + order.bindings + [.int64(Int64(limit))])
    }

    private static func searchOrder(
        sort: SearchSort,
        cursor: SearchPageCursor?
    ) -> (orderBy: String, predicate: String?, bindings: [SQLiteBindValue]) {
        switch (sort, cursor) {
        case (.relevance, .relevance(let rank, let modifiedAt, let entryID)):
            return (
                "relevance_rank ASC, modified_at DESC, id ASC",
                "(relevance_rank > ? OR (relevance_rank = ? AND modified_at < ?) OR (relevance_rank = ? AND modified_at = ? AND id > ?))",
                [.double(rank), .double(rank), .double(modifiedAt.timeIntervalSince1970), .double(rank), .double(modifiedAt.timeIntervalSince1970), .int64(entryID)]
            )
        case (.nameAscending, .text(let value, let entryID)):
            return ("search_name ASC, id ASC", "(search_name > ? OR (search_name = ? AND id > ?))", [.text(value), .text(value), .int64(entryID)])
        case (.nameDescending, .text(let value, let entryID)):
            return ("search_name DESC, id ASC", "(search_name < ? OR (search_name = ? AND id > ?))", [.text(value), .text(value), .int64(entryID)])
        case (.pathAscending, .text(let value, let entryID)):
            return ("search_path ASC, id ASC", "(search_path > ? OR (search_path = ? AND id > ?))", [.text(value), .text(value), .int64(entryID)])
        case (.pathDescending, .text(let value, let entryID)):
            return ("search_path DESC, id ASC", "(search_path < ? OR (search_path = ? AND id > ?))", [.text(value), .text(value), .int64(entryID)])
        case (.modifiedNewest, .date(let value, let entryID)):
            return ("modified_at DESC, id ASC", "(modified_at < ? OR (modified_at = ? AND id > ?))", [.double(value.timeIntervalSince1970), .double(value.timeIntervalSince1970), .int64(entryID)])
        case (.modifiedOldest, .date(let value, let entryID)):
            return ("modified_at ASC, id ASC", "(modified_at > ? OR (modified_at = ? AND id > ?))", [.double(value.timeIntervalSince1970), .double(value.timeIntervalSince1970), .int64(entryID)])
        case (.sizeLargest, .size(let value, let entryID)):
            return ("size_bytes DESC, id ASC", "(size_bytes < ? OR (size_bytes = ? AND id > ?))", [.int64(value), .int64(value), .int64(entryID)])
        case (.sizeSmallest, .size(let value, let entryID)):
            return ("size_bytes ASC, id ASC", "(size_bytes > ? OR (size_bytes = ? AND id > ?))", [.int64(value), .int64(value), .int64(entryID)])
        case (.kindThenName, .kind(let kind, let name, let entryID)):
            return (
                "kind ASC, search_name ASC, id ASC",
                "(kind > ? OR (kind = ? AND search_name > ?) OR (kind = ? AND search_name = ? AND id > ?))",
                [.text(kind), .text(kind), .text(name), .text(kind), .text(name), .int64(entryID)]
            )
        case (.relevance, nil):
            return ("relevance_rank ASC, modified_at DESC, id ASC", nil, [])
        case (.nameAscending, nil): return ("search_name ASC, id ASC", nil, [])
        case (.nameDescending, nil): return ("search_name DESC, id ASC", nil, [])
        case (.pathAscending, nil): return ("search_path ASC, id ASC", nil, [])
        case (.pathDescending, nil): return ("search_path DESC, id ASC", nil, [])
        case (.modifiedNewest, nil): return ("modified_at DESC, id ASC", nil, [])
        case (.modifiedOldest, nil): return ("modified_at ASC, id ASC", nil, [])
        case (.sizeLargest, nil): return ("size_bytes DESC, id ASC", nil, [])
        case (.sizeSmallest, nil): return ("size_bytes ASC, id ASC", nil, [])
        case (.kindThenName, nil): return ("kind ASC, search_name ASC, id ASC", nil, [])
        default:
            return ("relevance_rank ASC, modified_at DESC, id ASC", "0", [])
        }
    }

    private static func cursor(for entry: IndexedEntry, rank: Double, sort: SearchSort) -> SearchPageCursor {
        switch sort {
        case .relevance: .relevance(rank: rank, modifiedAt: entry.modifiedAt, entryID: entry.id)
        case .nameAscending, .nameDescending: .text(value: entry.searchName, entryID: entry.id)
        case .pathAscending, .pathDescending: .text(value: entry.searchPath, entryID: entry.id)
        case .modifiedNewest, .modifiedOldest: .date(value: entry.modifiedAt, entryID: entry.id)
        case .sizeLargest, .sizeSmallest: .size(value: entry.sizeBytes, entryID: entry.id)
        case .kindThenName: .kind(kind: entry.kind.rawValue, name: entry.searchName, entryID: entry.id)
        }
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
