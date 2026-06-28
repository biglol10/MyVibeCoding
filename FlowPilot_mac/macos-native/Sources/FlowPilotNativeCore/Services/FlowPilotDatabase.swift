import Foundation
import SQLite3

public enum FlowPilotDatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case invalidDate(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "데이터베이스를 열 수 없습니다: \(message)"
        case .prepareFailed(let message):
            return "쿼리를 준비할 수 없습니다: \(message)"
        case .stepFailed(let message):
            return "쿼리를 실행할 수 없습니다: \(message)"
        case .invalidDate(let value):
            return "날짜를 읽을 수 없습니다: \(value)"
        }
    }
}

public final class FlowPilotDatabase {
    private static let windowObservationRetentionInterval: TimeInterval = 2 * 86_400
    private let path: String

    public init(path: String) {
        self.path = path
    }

    public func dashboardDataForLocalToday(now: Date = Date()) throws -> DashboardReportData {
        let bounds = Self.localDayBounds(now: now)
        return try dashboardData(start: bounds.start, end: bounds.end)
    }

    public func dashboardDataForLocalWeek(now: Date = Date()) throws -> DashboardReportData {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart.addingTimeInterval(-6 * 86_400)
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400)
        return try dashboardData(start: start, end: end)
    }

    public func listRules() throws -> [ClassificationRule] {
        return try withConnection(flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX) { db in
            try Self.listRules(db: db)
        }
    }

    public func saveRule(_ rule: ClassificationRule) throws {
        try withConnection(flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX) { db in
            try Self.initializeSchema(db: db)
            try Self.saveRule(db: db, rule: rule)
        }
    }

    public func saveSessions(_ sessions: [ActivitySessionRecord]) throws {
        try withConnection(flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX) { db in
            try Self.initializeSchema(db: db)
            for session in sessions {
                try Self.saveSession(db: db, session: session)
            }
        }
    }

    public func saveWindowObservations(
        sessionID: String,
        observations: [WindowObservationRecord]
    ) throws {
        guard !observations.isEmpty else {
            return
        }

        try withConnection(flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX) { db in
            try Self.initializeSchema(db: db)
            let latestObservedAt = observations.map(\.observedAt).max() ?? Date()
            let retentionCutoff = latestObservedAt.addingTimeInterval(-Self.windowObservationRetentionInterval)
            try Self.pruneWindowObservations(db: db, before: retentionCutoff)
            for observation in observations {
                try Self.saveWindowObservation(db: db, sessionID: sessionID, observation: observation)
            }
        }
    }

    public func saveBrowserEvent(_ draft: BrowserEventDraft, occurredAt: Date = Date()) throws {
        try withConnection(flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX) { db in
            try Self.initializeSchema(db: db)
            try Self.saveBrowserEvent(db: db, draft: draft, occurredAt: occurredAt)
        }
    }

    public func listRecentBrowserEvents(limit: Int = 100) throws -> [BrowserEventRecord] {
        try withConnection(flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX) { db in
            try Self.listRecentBrowserEvents(db: db, limit: limit)
        }
    }

    private func dashboardData(start: Date, end: Date) throws -> DashboardReportData {
        try withConnection(flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX) { db in
            let sessions = try Self.listSessions(db: db, start: start, end: end)
            let rules = try Self.listRules(db: db)
            return ReportAggregator.dashboardData(sessions: sessions, rules: rules)
        }
    }

    private func withConnection<T>(
        flags: Int32,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let db {
                sqlite3_close(db)
            }
            throw FlowPilotDatabaseError.openFailed(message)
        }
        defer { sqlite3_close(db) }

        return try body(db)
    }

    private static func initializeSchema(db: OpaquePointer) throws {
        try execute(db: db, sql: """
            PRAGMA foreign_keys = ON;

            CREATE TABLE IF NOT EXISTS activity_sessions (
              id TEXT PRIMARY KEY,
              started_at TEXT NOT NULL,
              ended_at TEXT NOT NULL,
              duration_seconds INTEGER NOT NULL,
              source TEXT NOT NULL,
              app_name TEXT NOT NULL,
              process_name TEXT NOT NULL,
              window_title TEXT NOT NULL,
              domain TEXT,
              url TEXT,
              url_storage_mode TEXT NOT NULL DEFAULT 'domain',
              is_idle INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS classification_rules (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              rule_type TEXT NOT NULL,
              pattern TEXT NOT NULL,
              category TEXT NOT NULL,
              priority INTEGER NOT NULL DEFAULT 0,
              is_builtin INTEGER NOT NULL DEFAULT 0,
              is_enabled INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS browser_events (
              id TEXT PRIMARY KEY,
              occurred_at TEXT NOT NULL,
              domain TEXT NOT NULL,
              url TEXT,
              title TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS window_observations (
              id TEXT PRIMARY KEY,
              session_id TEXT,
              observed_at TEXT NOT NULL,
              app_name TEXT NOT NULL,
              process_name TEXT NOT NULL,
              pid INTEGER,
              bundle_identifier TEXT,
              window_title TEXT,
              is_visible INTEGER NOT NULL DEFAULT 0,
              is_frontmost INTEGER NOT NULL DEFAULT 0,
              is_primary INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              FOREIGN KEY(session_id) REFERENCES activity_sessions(id) ON DELETE SET NULL
            );

            CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON activity_sessions(started_at);
            CREATE INDEX IF NOT EXISTS idx_sessions_domain ON activity_sessions(domain);
            CREATE INDEX IF NOT EXISTS idx_rules_type_pattern ON classification_rules(rule_type, pattern);
            CREATE INDEX IF NOT EXISTS idx_browser_events_occurred_at ON browser_events(occurred_at);
            CREATE INDEX IF NOT EXISTS idx_browser_events_domain ON browser_events(domain);
            CREATE INDEX IF NOT EXISTS idx_window_observations_observed_at ON window_observations(observed_at);
            CREATE INDEX IF NOT EXISTS idx_window_observations_session_id ON window_observations(session_id);
            """)
    }

    private static func saveSession(db: OpaquePointer, session: ActivitySessionRecord) throws {
        let sql = """
            INSERT INTO activity_sessions (
              id, started_at, ended_at, duration_seconds, source, app_name, process_name,
              window_title, domain, url, url_storage_mode, is_idle, created_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 'domain', ?11, ?12)
            ON CONFLICT(id) DO UPDATE SET
              started_at = excluded.started_at,
              ended_at = excluded.ended_at,
              duration_seconds = excluded.duration_seconds,
              source = excluded.source,
              app_name = excluded.app_name,
              process_name = excluded.process_name,
              window_title = excluded.window_title,
              domain = excluded.domain,
              url = excluded.url,
              url_storage_mode = excluded.url_storage_mode,
              is_idle = excluded.is_idle
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw FlowPilotDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: session.id)
        bindText(statement, index: 2, value: formatDate(session.startedAt))
        bindText(statement, index: 3, value: formatDate(session.endedAt))
        sqlite3_bind_int64(statement, 4, Int64(session.durationSeconds))
        bindText(statement, index: 5, value: session.isIdle ? "idle" : "activeWindow")
        bindText(statement, index: 6, value: session.appName)
        bindText(statement, index: 7, value: session.processName)
        bindText(statement, index: 8, value: session.windowTitle)
        bindOptionalText(statement, index: 9, value: session.domain)
        bindOptionalText(statement, index: 10, value: session.url)
        sqlite3_bind_int64(statement, 11, session.isIdle ? 1 : 0)
        bindText(statement, index: 12, value: formatDate(Date()))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw FlowPilotDatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func saveBrowserEvent(
        db: OpaquePointer,
        draft: BrowserEventDraft,
        occurredAt: Date
    ) throws {
        let sql = """
            INSERT INTO browser_events (id, occurred_at, domain, url, title)
            VALUES (?1, ?2, ?3, ?4, ?5)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw FlowPilotDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: UUID().uuidString)
        bindText(statement, index: 2, value: formatDate(occurredAt))
        bindText(statement, index: 3, value: draft.domain)
        bindOptionalText(statement, index: 4, value: draft.url)
        bindText(statement, index: 5, value: draft.title)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw FlowPilotDatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func saveWindowObservation(
        db: OpaquePointer,
        sessionID: String,
        observation: WindowObservationRecord
    ) throws {
        let sql = """
            INSERT INTO window_observations (
              id, session_id, observed_at, app_name, process_name, pid, bundle_identifier,
              window_title, is_visible, is_frontmost, is_primary, created_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw FlowPilotDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: UUID().uuidString)
        bindText(statement, index: 2, value: sessionID)
        bindText(statement, index: 3, value: formatDate(observation.observedAt))
        bindText(statement, index: 4, value: observation.appName)
        bindText(statement, index: 5, value: observation.processName)
        if let pid = observation.pid {
            sqlite3_bind_int64(statement, 6, Int64(pid))
        } else {
            sqlite3_bind_null(statement, 6)
        }
        bindOptionalText(statement, index: 7, value: observation.bundleIdentifier)
        bindOptionalText(statement, index: 8, value: observation.windowTitle)
        sqlite3_bind_int64(statement, 9, observation.isVisible ? 1 : 0)
        sqlite3_bind_int64(statement, 10, observation.isFrontmost ? 1 : 0)
        sqlite3_bind_int64(statement, 11, observation.isPrimary ? 1 : 0)
        bindText(statement, index: 12, value: formatDate(Date()))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw FlowPilotDatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func pruneWindowObservations(db: OpaquePointer, before cutoff: Date) throws {
        let sql = "DELETE FROM window_observations WHERE julianday(observed_at) < julianday(?1)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw FlowPilotDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: formatDate(cutoff))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw FlowPilotDatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func saveRule(db: OpaquePointer, rule: ClassificationRule) throws {
        let sql = """
            INSERT INTO classification_rules (
              id, name, rule_type, pattern, category, priority, is_builtin, is_enabled,
              created_at, updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name,
              rule_type = excluded.rule_type,
              pattern = excluded.pattern,
              category = excluded.category,
              priority = excluded.priority,
              is_builtin = excluded.is_builtin,
              is_enabled = excluded.is_enabled,
              updated_at = excluded.updated_at
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw FlowPilotDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        let now = formatDate(Date())
        bindText(statement, index: 1, value: rule.id)
        bindText(statement, index: 2, value: rule.name)
        bindText(statement, index: 3, value: rule.ruleType.rawValue)
        bindText(statement, index: 4, value: canonicalRulePattern(rule.ruleType, rule.pattern) ?? rule.pattern)
        bindText(statement, index: 5, value: rule.category.databaseValue)
        sqlite3_bind_int64(statement, 6, Int64(rule.priority))
        sqlite3_bind_int64(statement, 7, rule.isBuiltin ? 1 : 0)
        sqlite3_bind_int64(statement, 8, rule.isEnabled ? 1 : 0)
        bindText(statement, index: 9, value: now)
        bindText(statement, index: 10, value: now)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw FlowPilotDatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func listRecentBrowserEvents(
        db: OpaquePointer,
        limit: Int
    ) throws -> [BrowserEventRecord] {
        let sql = """
            SELECT id, occurred_at, domain, url, title
            FROM browser_events
            ORDER BY occurred_at DESC
            LIMIT ?1
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw FlowPilotDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(limit))

        var events: [BrowserEventRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return events
            }
            guard result == SQLITE_ROW else {
                throw FlowPilotDatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }

            let occurredAtRaw = text(statement, 1)
            guard let occurredAt = parseDate(occurredAtRaw) else {
                throw FlowPilotDatabaseError.invalidDate(occurredAtRaw)
            }

            events.append(
                BrowserEventRecord(
                    id: text(statement, 0),
                    occurredAt: occurredAt,
                    domain: text(statement, 2),
                    url: optionalText(statement, 3),
                    title: text(statement, 4)
                )
            )
        }
    }

    private static func listSessions(
        db: OpaquePointer,
        start: Date,
        end: Date
    ) throws -> [ActivitySessionRecord] {
        let sql = """
            SELECT id, started_at, ended_at, duration_seconds, app_name, process_name,
                   window_title, domain, url, is_idle
            FROM activity_sessions
            WHERE julianday(started_at) >= julianday(?1)
              AND julianday(started_at) < julianday(?2)
            ORDER BY started_at ASC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw FlowPilotDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: formatDate(start))
        bindText(statement, index: 2, value: formatDate(end))

        var sessions: [ActivitySessionRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return sessions
            }
            guard result == SQLITE_ROW else {
                throw FlowPilotDatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }

            let startedAtRaw = text(statement, 1)
            let endedAtRaw = text(statement, 2)
            guard let startedAt = parseDate(startedAtRaw) else {
                throw FlowPilotDatabaseError.invalidDate(startedAtRaw)
            }
            guard let endedAt = parseDate(endedAtRaw) else {
                throw FlowPilotDatabaseError.invalidDate(endedAtRaw)
            }

            sessions.append(
                ActivitySessionRecord(
                    id: text(statement, 0),
                    startedAt: startedAt,
                    endedAt: endedAt,
                    durationSeconds: Int(sqlite3_column_int64(statement, 3)),
                    appName: text(statement, 4),
                    processName: text(statement, 5),
                    windowTitle: text(statement, 6),
                    domain: optionalText(statement, 7),
                    url: optionalText(statement, 8),
                    isIdle: sqlite3_column_int64(statement, 9) == 1
                )
            )
        }
    }

    private static func listRules(db: OpaquePointer) throws -> [ClassificationRule] {
        let sql = """
            SELECT id, name, rule_type, pattern, category, priority, is_builtin, is_enabled
            FROM classification_rules
            ORDER BY lower(name) ASC, lower(pattern) ASC, is_builtin ASC, priority DESC, id ASC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw FlowPilotDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var rules: [ClassificationRule] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return rules
            }
            guard result == SQLITE_ROW else {
                throw FlowPilotDatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
            guard let ruleType = RuleType(rawValue: text(statement, 2)) else {
                continue
            }

            rules.append(
                ClassificationRule(
                    id: text(statement, 0),
                    name: text(statement, 1),
                    ruleType: ruleType,
                    pattern: text(statement, 3),
                    category: ActivityCategory(databaseValue: text(statement, 4)),
                    priority: Int(sqlite3_column_int64(statement, 5)),
                    isBuiltin: sqlite3_column_int64(statement, 6) == 1,
                    isEnabled: sqlite3_column_int64(statement, 7) == 1
                )
            )
        }
    }

    private static func localDayBounds(now: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    public static func userRule(
        ruleType: RuleType,
        pattern: String,
        category: ActivityCategory,
        name: String? = nil
    ) throws -> ClassificationRule {
        guard category != .uncategorized, category != .idle else {
            throw FlowPilotDatabaseError.stepFailed("Uncategorized or idle cannot be used for rules.")
        }
        guard let canonicalPattern = canonicalRulePattern(ruleType, pattern) else {
            throw FlowPilotDatabaseError.stepFailed("Rule pattern cannot be blank.")
        }

        return ClassificationRule(
            id: "user:\(ruleType.rawValue):\(patternIDSegment(canonicalPattern))",
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? canonicalPattern,
            ruleType: ruleType,
            pattern: canonicalPattern,
            category: category,
            priority: 100,
            isBuiltin: false,
            isEnabled: true
        )
    }

    private static func canonicalRulePattern(_ ruleType: RuleType, _ pattern: String) -> String? {
        switch ruleType {
        case .domain:
            let normalized = pattern
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .removingWwwPrefix
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return normalized.isEmpty ? nil : normalized
        case .app, .titleKeyword, .urlPattern:
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func patternIDSegment(_ pattern: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-~")
        return pattern.unicodeScalars.map { scalar in
            if allowed.contains(scalar) {
                return String(scalar)
            }
            return String(format: "%%%02X", scalar.value)
        }.joined()
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: value)
    }

    private static func optionalText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        let value = text(statement, index)
        return value.isEmpty ? nil : value
    }

    private static func bindText(_ statement: OpaquePointer, index: Int32, value: String) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private static func bindOptionalText(_ statement: OpaquePointer, index: Int32, value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bindText(statement, index: index, value: value)
    }

    private static func execute(db: OpaquePointer, sql: String) throws {
        var error: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if result != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(error)
            throw FlowPilotDatabaseError.stepFailed(message)
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        fractionalDateFormatter.date(from: value) ?? internetDateFormatter.date(from: value)
    }

    private static func formatDate(_ date: Date) -> String {
        fractionalDateFormatter.string(from: date)
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let internetDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

private extension String {
    var removingWwwPrefix: String {
        hasPrefix("www.") ? String(dropFirst(4)) : self
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
