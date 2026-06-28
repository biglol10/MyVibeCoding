import XCTest
@testable import FlowPilotNativeCore

final class ReportAggregatorTests: XCTestCase {
    func testIgnoredSessionsAreExcludedFromSummaryUsageAndTimeline() {
        let ignored = session(id: "ignored", appName: "Finder", duration: 120)
        let productive = session(id: "productive", appName: "Codex", duration: 300)
        let rules = [
            rule(pattern: "Finder", category: .ignored),
            rule(pattern: "Codex", category: .productive)
        ]

        let data = ReportAggregator.dashboardData(sessions: [ignored, productive], rules: rules)

        XCTAssertEqual(data.summary.totalSeconds, 300)
        XCTAssertEqual(data.summary.productiveSeconds, 300)
        XCTAssertEqual(data.summary.sessionCount, 1)
        XCTAssertEqual(data.usageItems.map(\.name), ["Codex"])
        XCTAssertEqual(data.timelineSessions.map(\.name), ["Codex"])
    }

    func testDomainSessionsAggregateByDomainName() {
        let first = session(id: "one", appName: "Google Chrome", domain: "chatgpt.com", duration: 60)
        let second = session(id: "two", appName: "Google Chrome", domain: "chatgpt.com", duration: 90)
        let rules = [
            ClassificationRule(
                id: "builtin:chatgpt",
                name: "ChatGPT",
                ruleType: .domain,
                pattern: "chatgpt.com",
                category: .productive,
                priority: 0,
                isBuiltin: true,
                isEnabled: true
            )
        ]

        let data = ReportAggregator.dashboardData(sessions: [first, second], rules: rules)

        XCTAssertEqual(data.usageItems.count, 1)
        XCTAssertEqual(data.usageItems[0].name, "chatgpt.com")
        XCTAssertEqual(data.usageItems[0].durationSeconds, 150)
        XCTAssertEqual(data.usageItems[0].kind, "도메인")
        XCTAssertEqual(data.usageItems[0].ruleSource, "기본 규칙")
    }

    func testUserRuleNameOverridesUsageDisplayNameAsAlias() {
        let session = session(id: "one", appName: "Google Chrome", domain: "internal.example.com", duration: 60)
        let rules = [
            ClassificationRule(
                id: "user:domain:internal.example.com",
                name: "사내 포털",
                ruleType: .domain,
                pattern: "internal.example.com",
                category: .productive,
                priority: 100,
                isBuiltin: false,
                isEnabled: true
            )
        ]

        let data = ReportAggregator.dashboardData(sessions: [session], rules: rules)

        XCTAssertEqual(data.usageItems.map(\.name), ["사내 포털"])
        XCTAssertEqual(data.timelineSessions.map(\.name), ["사내 포털"])
        XCTAssertEqual(data.usageItems[0].ruleSource, "사용자 규칙")
    }

    private func rule(pattern: String, category: ActivityCategory) -> ClassificationRule {
        ClassificationRule(
            id: "user:app:\(pattern)",
            name: pattern,
            ruleType: .app,
            pattern: pattern,
            category: category,
            priority: 100,
            isBuiltin: false,
            isEnabled: true
        )
    }

    private func session(
        id: String,
        appName: String,
        domain: String? = nil,
        duration: Int
    ) -> ActivitySessionRecord {
        ActivitySessionRecord(
            id: id,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: TimeInterval(100 + duration)),
            durationSeconds: duration,
            appName: appName,
            processName: appName,
            windowTitle: appName,
            domain: domain,
            url: nil,
            isIdle: false
        )
    }
}
