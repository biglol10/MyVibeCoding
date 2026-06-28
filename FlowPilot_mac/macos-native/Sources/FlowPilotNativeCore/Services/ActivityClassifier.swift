import Foundation

public enum ActivityClassifier {
    public static func classify(
        session: ActivitySessionRecord,
        rules: [ClassificationRule]
    ) -> (category: ActivityCategory, rule: ClassificationRule?) {
        let enabledRules = rules.filter(\.isEnabled)
        let userRules = enabledRules.filter { !$0.isBuiltin }
        let builtinRules = enabledRules.filter(\.isBuiltin)

        if let userRule = bestMatchingRule(for: session, in: userRules) {
            return (userRule.category, userRule)
        }
        if let builtinRule = bestMatchingRule(for: session, in: builtinRules) {
            return (builtinRule.category, builtinRule)
        }
        return (.uncategorized, nil)
    }

    private static func bestMatchingRule(
        for session: ActivitySessionRecord,
        in rules: [ClassificationRule]
    ) -> ClassificationRule? {
        rules
            .filter { matches($0, session: session) }
            .max { lhs, rhs in isOrderedBefore(lhs, rhs) }
    }

    private static func matches(_ rule: ClassificationRule, session: ActivitySessionRecord) -> Bool {
        switch rule.ruleType {
        case .domain:
            guard
                let domain = session.domain.flatMap({ canonicalPattern(ruleType: .domain, pattern: $0) }),
                let pattern = canonicalPattern(ruleType: .domain, pattern: rule.pattern)
            else {
                return false
            }

            return domain == pattern
                || domain.hasSuffix(".\(pattern)")
                || domain.removingWwwPrefix == pattern
        case .app:
            return session.appName.caseInsensitiveCompare(rule.pattern) == .orderedSame
                || session.processName.caseInsensitiveCompare(rule.pattern) == .orderedSame
        case .titleKeyword:
            guard let pattern = nonEmptyLowercased(rule.pattern) else {
                return false
            }
            return session.windowTitle.lowercased().contains(pattern)
        case .urlPattern:
            guard let pattern = nonEmptyLowercased(rule.pattern) else {
                return false
            }
            return session.url?.lowercased().contains(pattern) ?? false
        }
    }

    private static func isOrderedBefore(
        _ lhs: ClassificationRule,
        _ rhs: ClassificationRule
    ) -> Bool {
        let lhsSpecificity = specificity(lhs.ruleType)
        let rhsSpecificity = specificity(rhs.ruleType)
        if lhsSpecificity != rhsSpecificity {
            return lhsSpecificity < rhsSpecificity
        }
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.pattern.count < rhs.pattern.count
    }

    private static func specificity(_ ruleType: RuleType) -> Int {
        switch ruleType {
        case .urlPattern: return 40
        case .domain: return 30
        case .app: return 20
        case .titleKeyword: return 10
        }
    }

    private static func canonicalPattern(ruleType: RuleType, pattern: String) -> String? {
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

    private static func nonEmptyLowercased(_ value: String) -> String? {
        let pattern = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return pattern.isEmpty ? nil : pattern
    }
}

private extension String {
    var removingWwwPrefix: String {
        hasPrefix("www.") ? String(dropFirst(4)) : self
    }
}
