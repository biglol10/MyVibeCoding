import XCTest
@testable import FlowPilotNativeCore

final class ActivityClassifierTests: XCTestCase {
    func testUserRulesOverrideBuiltinRules() {
        let session = activitySession(domain: "youtube.com", appName: "Google Chrome")
        let rules = [
            rule(id: "builtin:youtube", type: .domain, pattern: "youtube.com", category: .unproductive, isBuiltin: true),
            rule(id: "user:youtube", type: .domain, pattern: "youtube.com", category: .productive, isBuiltin: false)
        ]

        let result = ActivityClassifier.classify(session: session, rules: rules)

        XCTAssertEqual(result.category, .productive)
        XCTAssertEqual(result.rule?.id, "user:youtube")
    }

    func testSubdomainRuleBeatsParentDomainRule() {
        let session = activitySession(domain: "chzzk.naver.com", appName: "Google Chrome")
        let rules = [
            rule(id: "builtin:naver", type: .domain, pattern: "naver.com", category: .neutral, isBuiltin: true),
            rule(id: "builtin:chzzk", type: .domain, pattern: "chzzk.naver.com", category: .unproductive, isBuiltin: true)
        ]

        let result = ActivityClassifier.classify(session: session, rules: rules)

        XCTAssertEqual(result.category, .unproductive)
        XCTAssertEqual(result.rule?.id, "builtin:chzzk")
    }

    func testAppRuleMatchesAppNameCaseInsensitively() {
        let session = activitySession(domain: nil, appName: "Codex")
        let rules = [
            rule(id: "user:codex", type: .app, pattern: "codex", category: .productive, isBuiltin: false)
        ]

        let result = ActivityClassifier.classify(session: session, rules: rules)

        XCTAssertEqual(result.category, .productive)
    }

    private func rule(
        id: String,
        type: RuleType,
        pattern: String,
        category: ActivityCategory,
        isBuiltin: Bool
    ) -> ClassificationRule {
        ClassificationRule(
            id: id,
            name: id,
            ruleType: type,
            pattern: pattern,
            category: category,
            priority: 0,
            isBuiltin: isBuiltin,
            isEnabled: true
        )
    }

    private func activitySession(domain: String?, appName: String) -> ActivitySessionRecord {
        ActivitySessionRecord(
            id: UUID().uuidString,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 160),
            durationSeconds: 60,
            appName: appName,
            processName: appName,
            windowTitle: appName,
            domain: domain,
            url: nil,
            isIdle: false
        )
    }
}
