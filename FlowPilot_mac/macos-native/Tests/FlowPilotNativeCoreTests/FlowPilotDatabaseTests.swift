import SQLite3
import XCTest
@testable import FlowPilotNativeCore

final class FlowPilotDatabaseTests: XCTestCase {
    func testReadsTodaySessionsAndAppliesIgnoredRules() throws {
        let databaseURL = temporaryDatabaseURL()
        try createDatabase(at: databaseURL)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        try insertRule(
            databaseURL,
            id: "user:app:Finder",
            name: "Finder",
            type: "app",
            pattern: "Finder",
            category: "ignored",
            priority: 100,
            isBuiltin: false
        )
        try insertRule(
            databaseURL,
            id: "builtin:domain:chatgpt.com",
            name: "ChatGPT",
            type: "domain",
            pattern: "chatgpt.com",
            category: "productive",
            priority: 0,
            isBuiltin: true
        )
        try insertSession(
            databaseURL,
            id: "ignored-session",
            startedAt: todayStart.addingTimeInterval(60),
            duration: 120,
            appName: "Finder",
            domain: nil
        )
        try insertSession(
            databaseURL,
            id: "productive-session",
            startedAt: todayStart.addingTimeInterval(300),
            duration: 180,
            appName: "Google Chrome",
            domain: "chatgpt.com"
        )

        let data = try FlowPilotDatabase(path: databaseURL.path).dashboardDataForLocalToday(now: now)

        XCTAssertEqual(data.summary.totalSeconds, 180)
        XCTAssertEqual(data.summary.productiveSeconds, 180)
        XCTAssertEqual(data.summary.sessionCount, 1)
        XCTAssertEqual(data.usageItems.map(\.name), ["chatgpt.com"])
        XCTAssertEqual(data.timelineSessions.map(\.name), ["chatgpt.com"])
    }

    func testDefaultDatabaseURLMatchesTauriAppDataLocation() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        let url = FlowPilotReportStore.defaultDatabaseURL(homeDirectory: home)

        XCTAssertEqual(
            url.path,
            "/Users/example/Library/Application Support/app.flowpilot.desktop/time-manager.sqlite3"
        )
    }

    func testSaveSessionsCreatesSchemaAndUpsertsActivitySession() throws {
        let databaseURL = temporaryDatabaseURL()
        let database = FlowPilotDatabase(path: databaseURL.path)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        try database.saveSessions([
            ActivitySessionRecord(
                id: "native-session",
                startedAt: start,
                endedAt: start.addingTimeInterval(5),
                durationSeconds: 5,
                appName: "Codex",
                processName: "Codex",
                windowTitle: "Codex",
                domain: nil,
                url: nil,
                isIdle: false
            )
        ])
        try database.saveSessions([
            ActivitySessionRecord(
                id: "native-session",
                startedAt: start,
                endedAt: start.addingTimeInterval(20),
                durationSeconds: 20,
                appName: "Codex",
                processName: "Codex",
                windowTitle: "FlowPilot",
                domain: nil,
                url: nil,
                isIdle: false
            )
        ])

        let data = try database.dashboardDataForLocalToday(now: start)

        XCTAssertEqual(data.summary.totalSeconds, 20)
        XCTAssertEqual(data.summary.sessionCount, 1)
        XCTAssertEqual(data.timelineSessions[0].title, "FlowPilot")
    }

    func testSavesAndListsRecentBrowserEvents() throws {
        let databaseURL = temporaryDatabaseURL()
        let database = FlowPilotDatabase(path: databaseURL.path)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try database.saveBrowserEvent(
            BrowserEventDraft(domain: "github.com", url: nil, title: "GitHub"),
            occurredAt: now
        )
        try database.saveBrowserEvent(
            BrowserEventDraft(domain: "chatgpt.com", url: nil, title: "ChatGPT"),
            occurredAt: now.addingTimeInterval(10)
        )

        let events = try database.listRecentBrowserEvents(limit: 2)

        XCTAssertEqual(events.map(\.domain), ["chatgpt.com", "github.com"])
        XCTAssertEqual(events.map(\.title), ["ChatGPT", "GitHub"])
    }

    func testSavesAndListsClassificationRules() throws {
        let databaseURL = temporaryDatabaseURL()
        let database = FlowPilotDatabase(path: databaseURL.path)
        let rule = try FlowPilotDatabase.userRule(
            ruleType: .domain,
            pattern: " WWW.Example.COM. ",
            category: .productive
        )

        try database.saveRule(rule)

        let rules = try database.listRules()

        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].id, "user:domain:example.com")
        XCTAssertEqual(rules[0].pattern, "example.com")
        XCTAssertEqual(rules[0].category, .productive)
        XCTAssertFalse(rules[0].isBuiltin)
    }

    func testListRulesSortsByNameAscending() throws {
        let databaseURL = temporaryDatabaseURL()
        try createDatabase(at: databaseURL)
        let database = FlowPilotDatabase(path: databaseURL.path)

        try insertRule(
            databaseURL,
            id: "user:app:Zed",
            name: "Zed",
            type: "app",
            pattern: "Zed",
            category: "productive",
            priority: 100,
            isBuiltin: false
        )
        try insertRule(
            databaseURL,
            id: "builtin:domain:atlassian.net",
            name: "Atlassian",
            type: "domain",
            pattern: "atlassian.net",
            category: "productive",
            priority: 0,
            isBuiltin: true
        )
        try insertRule(
            databaseURL,
            id: "user:app:Code",
            name: "Code",
            type: "app",
            pattern: "Code",
            category: "productive",
            priority: 100,
            isBuiltin: false
        )

        let rules = try database.listRules()

        XCTAssertEqual(rules.map(\.name), ["Atlassian", "Code", "Zed"])
    }

    func testWeeklyDashboardIncludesPreviousSixLocalDays() throws {
        let databaseURL = temporaryDatabaseURL()
        try createDatabase(at: databaseURL)
        let database = FlowPilotDatabase(path: databaseURL.path)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        try insertRule(
            databaseURL,
            id: "user:app:Codex",
            name: "Codex",
            type: "app",
            pattern: "Codex",
            category: "productive",
            priority: 100,
            isBuiltin: false
        )
        try insertSession(
            databaseURL,
            id: "six-days-ago",
            startedAt: calendar.date(byAdding: .day, value: -6, to: todayStart)!.addingTimeInterval(60),
            duration: 120,
            appName: "Codex",
            domain: nil
        )
        try insertSession(
            databaseURL,
            id: "seven-days-ago",
            startedAt: calendar.date(byAdding: .day, value: -7, to: todayStart)!.addingTimeInterval(60),
            duration: 999,
            appName: "Codex",
            domain: nil
        )

        let data = try database.dashboardDataForLocalWeek(now: now)

        XCTAssertEqual(data.summary.totalSeconds, 120)
        XCTAssertEqual(data.summary.sessionCount, 1)
        XCTAssertEqual(data.usageItems.map(\.name), ["Codex"])
    }

    func testSavesWindowObservationsWithoutChangingActivitySessions() throws {
        let databaseURL = temporaryDatabaseURL()
        let database = FlowPilotDatabase(path: databaseURL.path)
        let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ActivitySessionRecord(
            id: "primary-session",
            startedAt: observedAt,
            endedAt: observedAt.addingTimeInterval(5),
            durationSeconds: 5,
            appName: "Codex",
            processName: "Codex",
            windowTitle: "Codex",
            domain: nil,
            url: nil,
            isIdle: false
        )

        try database.saveSessions([session])
        try database.saveWindowObservations(
            sessionID: session.id,
            observations: [
                WindowObservationRecord(
                    observedAt: observedAt,
                    appName: "Codex",
                    processName: "Codex",
                    pid: 100,
                    bundleIdentifier: "com.openai.codex",
                    windowTitle: "Codex",
                    isVisible: true,
                    isFrontmost: true,
                    isPrimary: true
                ),
                WindowObservationRecord(
                    observedAt: observedAt,
                    appName: "Finder",
                    processName: "Finder",
                    pid: 200,
                    bundleIdentifier: "com.apple.finder",
                    windowTitle: "Downloads",
                    isVisible: true,
                    isFrontmost: false,
                    isPrimary: false
                )
            ]
        )

        try withWritableDatabase(databaseURL) { db in
            let observationCount = try intValue(db, "SELECT COUNT(*) FROM window_observations")
            let primaryCount = try intValue(
                db,
                "SELECT COUNT(*) FROM window_observations WHERE session_id='primary-session' AND is_primary=1"
            )
            let sessionCount = try intValue(db, "SELECT COUNT(*) FROM activity_sessions")

            XCTAssertEqual(observationCount, 2)
            XCTAssertEqual(primaryCount, 1)
            XCTAssertEqual(sessionCount, 1)
        }
    }

    func testSaveWindowObservationsPrunesOldAuxiliaryRows() throws {
        let databaseURL = temporaryDatabaseURL()
        let database = FlowPilotDatabase(path: databaseURL.path)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = now.addingTimeInterval(-3 * 86_400)

        try database.saveSessions([
            ActivitySessionRecord(
                id: "old-session",
                startedAt: old,
                endedAt: old.addingTimeInterval(5),
                durationSeconds: 5,
                appName: "Old App",
                processName: "Old App",
                windowTitle: "Old",
                domain: nil,
                url: nil,
                isIdle: false
            ),
            ActivitySessionRecord(
                id: "new-session",
                startedAt: now,
                endedAt: now.addingTimeInterval(5),
                durationSeconds: 5,
                appName: "New App",
                processName: "New App",
                windowTitle: "New",
                domain: nil,
                url: nil,
                isIdle: false
            )
        ])
        try database.saveWindowObservations(
            sessionID: "old-session",
            observations: [
                WindowObservationRecord(
                    observedAt: old,
                    appName: "Old App",
                    processName: "Old App",
                    pid: 100,
                    bundleIdentifier: nil,
                    windowTitle: "Old",
                    isVisible: true,
                    isFrontmost: false,
                    isPrimary: false
                )
            ]
        )
        try database.saveWindowObservations(
            sessionID: "new-session",
            observations: [
                WindowObservationRecord(
                    observedAt: now,
                    appName: "New App",
                    processName: "New App",
                    pid: 200,
                    bundleIdentifier: nil,
                    windowTitle: "New",
                    isVisible: true,
                    isFrontmost: true,
                    isPrimary: true
                )
            ]
        )

        try withWritableDatabase(databaseURL) { db in
            let oldRows = try intValue(
                db,
                "SELECT COUNT(*) FROM window_observations WHERE app_name='Old App'"
            )
            let newRows = try intValue(
                db,
                "SELECT COUNT(*) FROM window_observations WHERE app_name='New App'"
            )

            XCTAssertEqual(oldRows, 0)
            XCTAssertEqual(newRows, 1)
        }
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("flowpilot-native-\(UUID().uuidString)")
            .appendingPathExtension("sqlite3")
    }

    private func createDatabase(at url: URL) throws {
        try withWritableDatabase(url) { db in
            try execute(db, """
                CREATE TABLE activity_sessions (
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
                CREATE TABLE classification_rules (
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
                """)
        }
    }

    private func insertRule(
        _ url: URL,
        id: String,
        name: String,
        type: String,
        pattern: String,
        category: String,
        priority: Int,
        isBuiltin: Bool
    ) throws {
        try withWritableDatabase(url) { db in
            try execute(
                db,
                """
                INSERT INTO classification_rules (
                  id, name, rule_type, pattern, category, priority, is_builtin, is_enabled,
                  created_at, updated_at
                ) VALUES (
                  '\(id)', '\(name)', '\(type)', '\(pattern)', '\(category)', \(priority),
                  \(isBuiltin ? 1 : 0), 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
                );
                """
            )
        }
    }

    private func insertSession(
        _ url: URL,
        id: String,
        startedAt: Date,
        duration: Int,
        appName: String,
        domain: String?
    ) throws {
        let startedAtText = Self.formatter.string(from: startedAt)
        let endedAtText = Self.formatter.string(from: startedAt.addingTimeInterval(TimeInterval(duration)))
        let domainValue = domain.map { "'\($0)'" } ?? "NULL"

        try withWritableDatabase(url) { db in
            try execute(
                db,
                """
                INSERT INTO activity_sessions (
                  id, started_at, ended_at, duration_seconds, source, app_name, process_name,
                  window_title, domain, url, url_storage_mode, is_idle, created_at
                ) VALUES (
                  '\(id)', '\(startedAtText)', '\(endedAtText)', \(duration), 'activeWindow',
                  '\(appName)', '\(appName)', '\(appName)', \(domainValue), NULL, 'domain',
                  0, '2026-01-01T00:00:00Z'
                );
                """
            )
        }
    }

    private func withWritableDatabase(_ url: URL, body: (OpaquePointer) throws -> Void) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        guard let db else {
            return
        }
        defer { sqlite3_close(db) }
        try body(db)
    }

    private func execute(_ db: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if result != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown sqlite error"
            sqlite3_free(error)
            XCTFail(message)
        }
    }

    private func intValue(_ db: OpaquePointer, _ sql: String) throws -> Int {
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK)
        guard let statement else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
