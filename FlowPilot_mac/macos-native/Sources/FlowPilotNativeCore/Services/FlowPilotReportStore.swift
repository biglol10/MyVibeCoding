import Combine
import Foundation

public final class FlowPilotReportStore: ObservableObject {
    @Published public private(set) var summary: DashboardSummary
    @Published public private(set) var usageItems: [UsageItem]
    @Published public private(set) var timelineSessions: [TimelineSession]
    @Published public private(set) var weeklyData: DashboardReportData
    @Published public private(set) var rules: [ClassificationRule]
    @Published public private(set) var uncategorizedItems: [UncategorizedItem]
    @Published public private(set) var dataSourceLabel: String
    @Published public private(set) var lastError: String?

    private let databaseURL: URL
    private let fallback: SampleReportStore

    public init(
        databaseURL: URL = FlowPilotReportStore.defaultDatabaseURL(),
        fallback: SampleReportStore = SampleReportStore()
    ) {
        self.databaseURL = databaseURL
        self.fallback = fallback
        self.summary = fallback.summary
        self.usageItems = fallback.usageItems
        self.timelineSessions = fallback.timelineSessions
        self.weeklyData = DashboardReportData(
            summary: fallback.summary,
            usageItems: fallback.usageItems,
            timelineSessions: fallback.timelineSessions
        )
        self.rules = []
        self.uncategorizedItems = []
        self.dataSourceLabel = "샘플 데이터"
        refresh()
    }

    public func refresh(now: Date = Date()) {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            applyFallback()
            return
        }

        do {
            let database = FlowPilotDatabase(path: databaseURL.path)
            let data = try database.dashboardDataForLocalToday(now: now)
            let week = try database.dashboardDataForLocalWeek(now: now)
            let rules = try database.listRules()
            summary = data.summary
            usageItems = data.usageItems
            timelineSessions = data.timelineSessions
            weeklyData = week
            self.rules = rules.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            uncategorizedItems = Self.uncategorizedItems(from: data)
            dataSourceLabel = "기존 FlowPilot 데이터"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            applyFallback()
        }
    }

    public func saveRule(
        ruleType: RuleType,
        pattern: String,
        category: ActivityCategory,
        name: String? = nil
    ) throws {
        let database = FlowPilotDatabase(path: databaseURL.path)
        let rule = try FlowPilotDatabase.userRule(
            ruleType: ruleType,
            pattern: pattern,
            category: category,
            name: name
        )
        try database.saveRule(rule)
        refresh()
    }

    public static func defaultDatabaseURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("app.flowpilot.desktop")
            .appendingPathComponent("time-manager.sqlite3")
    }

    private func applyFallback() {
        summary = fallback.summary
        usageItems = fallback.usageItems
        timelineSessions = fallback.timelineSessions
        weeklyData = DashboardReportData(
            summary: fallback.summary,
            usageItems: fallback.usageItems,
            timelineSessions: fallback.timelineSessions
        )
        rules = []
        uncategorizedItems = Self.uncategorizedItems(from: weeklyData)
        dataSourceLabel = "샘플 데이터"
    }

    private static func uncategorizedItems(from data: DashboardReportData) -> [UncategorizedItem] {
        let counts = Dictionary(grouping: data.timelineSessions, by: \.name)
            .mapValues(\.count)

        return data.usageItems
            .filter { $0.category == .uncategorized }
            .map { item in
                let ruleType: RuleType = item.kind == "도메인" ? .domain : .app
                return UncategorizedItem(
                    id: "\(ruleType.rawValue):\(item.name)",
                    name: item.name,
                    ruleType: ruleType,
                    pattern: item.name,
                    durationSeconds: item.durationSeconds,
                    sessionCount: counts[item.name] ?? 0
                )
            }
            .sorted {
                if $0.durationSeconds == $1.durationSeconds {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.durationSeconds > $1.durationSeconds
            }
    }
}
