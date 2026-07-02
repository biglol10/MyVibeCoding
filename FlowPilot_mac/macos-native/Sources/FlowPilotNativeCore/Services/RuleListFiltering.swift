import Foundation

public enum RuleListFiltering {
    public static func visibleRules(
        from rules: [ClassificationRule],
        query: String
    ) -> [ClassificationRule] {
        let sortedRules = rules.sorted { lhs, rhs in
            let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            let patternComparison = lhs.pattern.localizedCaseInsensitiveCompare(rhs.pattern)
            if patternComparison != .orderedSame {
                return patternComparison == .orderedAscending
            }

            return lhs.id < rhs.id
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return sortedRules
        }

        return sortedRules.filter { rule in
            searchableText(for: rule).contains(normalizedQuery)
        }
    }

    private static func searchableText(for rule: ClassificationRule) -> String {
        [
            rule.name,
            rule.pattern,
            rule.ruleType.koreanLabel,
            rule.category.koreanLabel,
            rule.isBuiltin ? "기본 규칙" : "사용자 규칙"
        ]
        .joined(separator: " ")
        .lowercased()
    }
}
