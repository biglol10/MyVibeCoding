import Foundation
import SQLite3

public enum SQLiteIndexError: Error, LocalizedError, Sendable {
    case capabilityUnavailable(String)
    case openFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case executeFailed(String)
    case invalidData(String)

    public var errorDescription: String? {
        switch self {
        case .capabilityUnavailable(let message):
            return "Required SQLite FTS5 capability is unavailable: \(message)"
        case .openFailed(let message):
            return "Could not open the search index: \(message)"
        case .prepareFailed(let message):
            return "Could not prepare an index query: \(message)"
        case .bindFailed(let message):
            return "Could not bind an index query: \(message)"
        case .stepFailed(let message):
            return "Could not execute an index query: \(message)"
        case .executeFailed(let message):
            return "Could not update the search index: \(message)"
        case .invalidData(let message):
            return "The search index contains invalid data: \(message)"
        }
    }
}

enum SQLiteBindValue {
    case text(String)
    case int64(Int64)
    case double(Double)
    case null
}

final class SQLiteConnection {
    let handle: OpaquePointer

    init(path: String, flags: Int32) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(path, &database, flags, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite returned \(result)"
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteIndexError.openFailed(message)
        }
        handle = database

        let timeoutResult = sqlite3_busy_timeout(database, 2_000)
        guard timeoutResult == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(database))
            sqlite3_close(database)
            throw SQLiteIndexError.openFailed(message)
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    var errorMessage: String {
        String(cString: sqlite3_errmsg(handle))
    }

    func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(errorPointer)
            throw SQLiteIndexError.executeFailed(message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteIndexError.prepareFailed(errorMessage)
        }
        return SQLiteStatement(connection: self, handle: statement)
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}

final class SQLiteStatement {
    private unowned let connection: SQLiteConnection
    private let handle: OpaquePointer

    init(connection: SQLiteConnection, handle: OpaquePointer) {
        self.connection = connection
        self.handle = handle
    }

    deinit {
        sqlite3_finalize(handle)
    }

    func bind(_ values: [SQLiteBindValue]) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text):
                result = sqlite3_bind_text(
                    handle,
                    index,
                    text,
                    -1,
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                )
            case .int64(let integer):
                result = sqlite3_bind_int64(handle, index, integer)
            case .double(let double):
                result = sqlite3_bind_double(handle, index, double)
            case .null:
                result = sqlite3_bind_null(handle, index)
            }
            guard result == SQLITE_OK else {
                throw SQLiteIndexError.bindFailed(connection.errorMessage)
            }
        }
    }

    func step() throws -> Int32 {
        let result = sqlite3_step(handle)
        guard result == SQLITE_ROW || result == SQLITE_DONE else {
            throw SQLiteIndexError.stepFailed(connection.errorMessage)
        }
        return result
    }

    func reset() throws {
        let resetResult = sqlite3_reset(handle)
        let clearResult = sqlite3_clear_bindings(handle)
        guard resetResult == SQLITE_OK, clearResult == SQLITE_OK else {
            throw SQLiteIndexError.stepFailed(connection.errorMessage)
        }
    }

    func int64(at index: Int32) -> Int64 {
        sqlite3_column_int64(handle, index)
    }

    func double(at index: Int32) -> Double {
        sqlite3_column_double(handle, index)
    }

    func text(at index: Int32) throws -> String {
        guard let pointer = sqlite3_column_text(handle, index) else {
            throw SQLiteIndexError.invalidData("Expected text in column \(index)")
        }
        return String(cString: pointer)
    }

    func optionalInt64(at index: Int32) -> Int64? {
        guard sqlite3_column_type(handle, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(handle, index)
    }
}
