import XCTest
@testable import FlowPilotNativeCore

final class RuleListFilteringTests: XCTestCase {
    func testSortsRulesByNameAscendingForDisplay() {
        let rules = [
            rule(id: "zoom", name: "Zoom", pattern: "zoom.us"),
            rule(id: "chatgpt", name: "ChatGPT", pattern: "chatgpt.com"),
            rule(id: "atlassian", name: "Atlassian", pattern: "atlassian.net")
        ]

        let visibleRules = RuleListFiltering.visibleRules(from: rules, query: "")

        XCTAssertEqual(visibleRules.map(\.name), ["Atlassian", "ChatGPT", "Zoom"])
    }

    func testFiltersRulesByNamePatternTypeCategoryAndSource() {
        let rules = [
            rule(id: "chatgpt", name: "ChatGPT", pattern: "chatgpt.com", isBuiltin: true),
            rule(id: "claude", name: "Claude", ruleType: .app, pattern: "Claude", isBuiltin: false),
            rule(id: "youtube", name: "YouTube", pattern: "youtube.com", category: .unproductive, isBuiltin: true)
        ]

        XCTAssertEqual(
            RuleListFiltering.visibleRules(from: rules, query: "youtube").map(\.name),
            ["YouTube"]
        )
        XCTAssertEqual(
            RuleListFiltering.visibleRules(from: rules, query: "앱").map(\.name),
            ["Claude"]
        )
        XCTAssertEqual(
            RuleListFiltering.visibleRules(from: rules, query: "사용자").map(\.name),
            ["Claude"]
        )
        XCTAssertEqual(
            RuleListFiltering.visibleRules(from: rules, query: "비생산").map(\.name),
            ["YouTube"]
        )
    }

    private func rule(
        id: String,
        name: String,
        ruleType: RuleType = .domain,
        pattern: String,
        category: ActivityCategory = .productive,
        isBuiltin: Bool = false
    ) -> ClassificationRule {
        ClassificationRule(
            id: id,
            name: name,
            ruleType: ruleType,
            pattern: pattern,
            category: category,
            priority: isBuiltin ? 0 : 100,
            isBuiltin: isBuiltin,
            isEnabled: true
        )
    }
}
