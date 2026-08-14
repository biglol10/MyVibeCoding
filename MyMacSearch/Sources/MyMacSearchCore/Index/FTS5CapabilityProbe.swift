import SQLite3

public enum FTS5CapabilityProbe {
    public static func verify() throws {
        try verify(tokenizer: "trigram")
    }

    static func verify(tokenizer: String) throws {
        do {
            let connection = try SQLiteConnection(
                path: ":memory:",
                flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            )
            let option = try connection.prepare("SELECT sqlite_compileoption_used('ENABLE_FTS5')")
            guard try option.step() == SQLITE_ROW, option.int64(at: 0) == 1 else {
                throw SQLiteIndexError.capabilityUnavailable("SQLite was built without ENABLE_FTS5")
            }

            let quotedTokenizer = tokenizer.replacingOccurrences(of: "'", with: "''")
            try connection.execute(
                "CREATE VIRTUAL TABLE capability_probe USING fts5(name, path, tokenize='\(quotedTokenizer)')"
            )
            let insert = try connection.prepare("INSERT INTO capability_probe(name, path) VALUES (?, ?)")
            try insert.bind([.text("Report.swift"), .text("/Downloads/AnnualReport.swift")])
            guard try insert.step() == SQLITE_DONE else {
                throw SQLiteIndexError.capabilityUnavailable("Could not insert an FTS5 probe row")
            }

            let search = try connection.prepare(
                "SELECT count(*) FROM capability_probe WHERE capability_probe MATCH ?"
            )
            try search.bind([.text("\"port.s\"")])
            guard try search.step() == SQLITE_ROW, search.int64(at: 0) == 1 else {
                throw SQLiteIndexError.capabilityUnavailable("FTS5 trigram punctuation search failed")
            }
        } catch let error as SQLiteIndexError {
            if case .capabilityUnavailable = error {
                throw error
            }
            throw SQLiteIndexError.capabilityUnavailable(error.localizedDescription)
        } catch {
            throw SQLiteIndexError.capabilityUnavailable(error.localizedDescription)
        }
    }
}
