import XCTest
@testable import FlowPilotNativeCore

final class FlowPilotReportStoreTests: XCTestCase {
    func testMissingDatabaseUsesOrdinarySampleDataWithoutError() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FlowPilotReportStore(databaseURL: url)

        XCTAssertEqual(store.dataSourceLabel, "샘플 데이터")
        XCTAssertNil(store.lastError)
    }

    func testUnreadableExistingDatabaseLabelsFallbackAsError() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = midday()
        let fallback = SampleReportStore(now: now)
        try Data("not a sqlite database".utf8).write(to: url)

        let store = FlowPilotReportStore(databaseURL: url, fallback: fallback)

        XCTAssertEqual(store.dataSourceLabel, "샘플 데이터 (데이터베이스 오류)")
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(store.summary, fallback.summary)
        XCTAssertEqual(store.usageItems, fallback.usageItems)
        XCTAssertEqual(store.timelineSessions, fallback.timelineSessions)
        XCTAssertEqual(
            store.weeklyData,
            DashboardReportData(
                summary: fallback.summary,
                usageItems: fallback.usageItems,
                timelineSessions: fallback.timelineSessions
            )
        )
        XCTAssertEqual(store.rules, [])
        XCTAssertEqual(
            store.uncategorizedItems,
            [
                UncategorizedItem(
                    id: "app:capturestudio.app",
                    name: "capturestudio.app",
                    ruleType: .app,
                    pattern: "capturestudio.app",
                    durationSeconds: 4_200,
                    sessionCount: 1
                )
            ]
        )
    }

    func testRefreshKeepsLastGoodDataAndClearsErrorAfterRecovery() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = midday()
        let database = FlowPilotDatabase(path: url.path)
        try database.saveSessions([
            session(
                id: "first-focused",
                at: now.addingTimeInterval(-180),
                duration: 60,
                appName: "Focused App",
                windowTitle: "Design brief"
            ),
            session(
                id: "first-domain",
                at: now.addingTimeInterval(-90),
                duration: 40,
                appName: "Safari",
                windowTitle: "Reference notes",
                domain: "docs.example.com"
            )
        ])
        try database.saveRule(
            FlowPilotDatabase.userRule(
                ruleType: .app,
                pattern: "Focused App",
                category: .productive,
                name: "Focus Work"
            )
        )
        let store = FlowPilotReportStore(databaseURL: url)
        store.refresh(now: now)
        XCTAssertEqual(store.summary, DashboardSummary(
            totalSeconds: 100,
            productiveSeconds: 60,
            unproductiveSeconds: 0,
            idleSeconds: 0,
            sessionCount: 2
        ))
        XCTAssertEqual(store.usageItems.map(\.name), ["Focus Work", "docs.example.com"])
        XCTAssertEqual(store.timelineSessions.map(\.title), ["Design brief", "Reference notes"])
        XCTAssertEqual(store.weeklyData.summary.sessionCount, 2)
        XCTAssertEqual(store.rules.map(\.name), ["Focus Work"])
        XCTAssertEqual(store.uncategorizedItems.map(\.name), ["docs.example.com"])
        let loadedState = state(of: store)

        try FileManager.default.removeItem(at: url)
        try Data("not a sqlite database".utf8).write(to: url)
        store.refresh(now: now)

        XCTAssertEqual(state(of: store), loadedState)
        XCTAssertEqual(store.dataSourceLabel, "마지막 정상 데이터 (데이터베이스 오류)")
        XCTAssertNotNil(store.lastError)

        try FileManager.default.removeItem(at: url)
        let recoveredDatabase = FlowPilotDatabase(path: url.path)
        try recoveredDatabase.saveSessions([
            session(
                id: "recovered",
                at: now.addingTimeInterval(-30),
                duration: 25,
                appName: "Recovery App",
                windowTitle: "Recovered report"
            )
        ])
        try recoveredDatabase.saveRule(
            FlowPilotDatabase.userRule(
                ruleType: .app,
                pattern: "Recovery App",
                category: .unproductive,
                name: "Recovered Review"
            )
        )
        store.refresh(now: now)

        XCTAssertNotEqual(state(of: store), loadedState)
        XCTAssertEqual(store.summary, DashboardSummary(
            totalSeconds: 25,
            productiveSeconds: 0,
            unproductiveSeconds: 25,
            idleSeconds: 0,
            sessionCount: 1
        ))
        XCTAssertEqual(store.usageItems.map(\.name), ["Recovered Review"])
        XCTAssertEqual(store.timelineSessions.map(\.title), ["Recovered report"])
        XCTAssertEqual(store.weeklyData.summary.sessionCount, 1)
        XCTAssertEqual(store.rules.map(\.name), ["Recovered Review"])
        XCTAssertEqual(store.uncategorizedItems, [])
        XCTAssertEqual(store.dataSourceLabel, "기존 FlowPilot 데이터")
        XCTAssertNil(store.lastError)
    }

    func testMissingDatabaseResetsLastGoodStateBeforeLaterCorruptDatabase() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = midday()
        try FlowPilotDatabase(path: url.path).saveSessions([
            session(id: "loaded", at: now.addingTimeInterval(-60))
        ])
        let store = FlowPilotReportStore(databaseURL: url)
        store.refresh(now: now)
        XCTAssertEqual(store.dataSourceLabel, "기존 FlowPilot 데이터")

        try FileManager.default.removeItem(at: url)
        store.refresh(now: now)

        XCTAssertEqual(store.dataSourceLabel, "샘플 데이터")
        XCTAssertNil(store.lastError)

        try Data("not a sqlite database".utf8).write(to: url)
        store.refresh(now: now)

        XCTAssertEqual(store.dataSourceLabel, "샘플 데이터 (데이터베이스 오류)")
        XCTAssertNotNil(store.lastError)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("flowpilot-report-store-\(UUID().uuidString)")
            .appendingPathExtension("sqlite3")
    }

    private func midday() -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    }

    private func session(
        id: String,
        at date: Date,
        duration: Int = 5,
        appName: String = "Codex",
        windowTitle: String = "Project",
        domain: String? = nil
    ) -> ActivitySessionRecord {
        ActivitySessionRecord(
            id: id,
            startedAt: date,
            endedAt: date.addingTimeInterval(TimeInterval(duration)),
            durationSeconds: duration,
            appName: appName,
            processName: appName,
            windowTitle: windowTitle,
            domain: domain,
            url: nil,
            isIdle: false
        )
    }

    private func state(of store: FlowPilotReportStore) -> ReportStoreState {
        ReportStoreState(
            summary: store.summary,
            usageItems: store.usageItems,
            timelineSessions: store.timelineSessions,
            weeklyData: store.weeklyData,
            rules: store.rules,
            uncategorizedItems: store.uncategorizedItems
        )
    }

    private struct ReportStoreState: Equatable {
        let summary: DashboardSummary
        let usageItems: [UsageItem]
        let timelineSessions: [TimelineSession]
        let weeklyData: DashboardReportData
        let rules: [ClassificationRule]
        let uncategorizedItems: [UncategorizedItem]
    }
}
