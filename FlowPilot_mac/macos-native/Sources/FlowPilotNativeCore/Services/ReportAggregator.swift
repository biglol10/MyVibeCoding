import Foundation

public enum ReportAggregator {
    public static func dashboardData(
        sessions: [ActivitySessionRecord],
        rules: [ClassificationRule]
    ) -> DashboardReportData {
        var usageByName: [String: (seconds: Int, category: ActivityCategory, ruleSource: String, kind: String)] = [:]
        var timeline: [TimelineSession] = []

        var totalSeconds = 0
        var productiveSeconds = 0
        var unproductiveSeconds = 0
        var idleSeconds = 0

        for session in sessions where session.durationSeconds > 0 {
            let classification = ActivityClassifier.classify(session: session, rules: rules)
            var category = session.isIdle ? ActivityCategory.idle : classification.category

            if category == .ignored {
                continue
            }

            if session.isIdle {
                category = .idle
            }

            let rawDisplayName = session.domain ?? session.appName
            let displayName = classification.rule?.isBuiltin == false
                ? classification.rule?.name ?? rawDisplayName
                : rawDisplayName
            let ruleSource = classification.rule == nil
                ? "규칙 없음"
                : (classification.rule?.isBuiltin == true ? "기본 규칙" : "사용자 규칙")
            let kind = session.domain == nil ? "앱" : "도메인"

            totalSeconds += session.durationSeconds
            switch category {
            case .productive:
                productiveSeconds += session.durationSeconds
            case .unproductive:
                unproductiveSeconds += session.durationSeconds
            case .idle:
                idleSeconds += session.durationSeconds
            case .neutral, .uncategorized, .ignored:
                break
            }

            let existing = usageByName[displayName]
            usageByName[displayName] = (
                seconds: (existing?.seconds ?? 0) + session.durationSeconds,
                category: existing?.category ?? category,
                ruleSource: existing?.ruleSource ?? ruleSource,
                kind: existing?.kind ?? kind
            )

            timeline.append(
                TimelineSession(
                    id: UUID(uuidString: session.id) ?? UUID(),
                    name: displayName,
                    title: session.windowTitle.isEmpty ? nil : session.windowTitle,
                    category: category,
                    startedAt: session.startedAt,
                    endedAt: session.endedAt
                )
            )
        }

        let usageItems = usageByName
            .map { name, aggregate in
                UsageItem(
                    id: UUID(),
                    name: name,
                    kind: aggregate.kind,
                    category: aggregate.category,
                    durationSeconds: aggregate.seconds,
                    share: totalSeconds == 0 ? 0 : Double(aggregate.seconds) / Double(totalSeconds),
                    ruleSource: aggregate.ruleSource
                )
            }
            .sorted {
                if $0.durationSeconds == $1.durationSeconds {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.durationSeconds > $1.durationSeconds
            }

        return DashboardReportData(
            summary: DashboardSummary(
                totalSeconds: totalSeconds,
                productiveSeconds: productiveSeconds,
                unproductiveSeconds: unproductiveSeconds,
                idleSeconds: idleSeconds,
                sessionCount: timeline.count
            ),
            usageItems: usageItems,
            timelineSessions: timeline.sorted { $0.startedAt < $1.startedAt }
        )
    }
}
