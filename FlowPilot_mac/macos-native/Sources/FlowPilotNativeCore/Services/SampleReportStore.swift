import Combine
import Foundation

public final class SampleReportStore: ObservableObject {
    public let summary: DashboardSummary
    public let usageItems: [UsageItem]
    public let timelineSessions: [TimelineSession]

    public init(now: Date = Date()) {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 9, minute: 20, second: 0, of: now) ?? now

        let usageItems = [
            UsageItem(
                id: UUID(),
                name: "Codex",
                kind: "앱",
                category: .productive,
                durationSeconds: 6_420,
                share: 0.55,
                ruleSource: "사용자 규칙"
            ),
            UsageItem(
                id: UUID(),
                name: "capturestudio.app",
                kind: "앱",
                category: .uncategorized,
                durationSeconds: 4_200,
                share: 0.36,
                ruleSource: "규칙 없음"
            ),
            UsageItem(
                id: UUID(),
                name: "chatgpt.com",
                kind: "도메인",
                category: .productive,
                durationSeconds: 1_080,
                share: 0.09,
                ruleSource: "기본 규칙"
            )
        ]

        self.usageItems = usageItems.sorted { $0.durationSeconds > $1.durationSeconds }
        self.timelineSessions = [
            TimelineSession(
                id: UUID(),
                name: "Codex",
                title: "FlowPilot 작업",
                category: .productive,
                startedAt: start,
                endedAt: start.addingTimeInterval(2_940)
            ),
            TimelineSession(
                id: UUID(),
                name: "capturestudio.app",
                title: "화면 캡처",
                category: .uncategorized,
                startedAt: start.addingTimeInterval(2_940),
                endedAt: start.addingTimeInterval(7_140)
            ),
            TimelineSession(
                id: UUID(),
                name: "chatgpt.com",
                title: "SwiftUI 설계",
                category: .productive,
                startedAt: start.addingTimeInterval(7_140),
                endedAt: start.addingTimeInterval(8_220)
            )
        ]

        let total = usageItems.map(\.durationSeconds).reduce(0, +)
        let productive = usageItems.filter { $0.category == .productive }.map(\.durationSeconds).reduce(0, +)
        let unproductive = usageItems.filter { $0.category == .unproductive }.map(\.durationSeconds).reduce(0, +)
        let idle = usageItems.filter { $0.category == .idle }.map(\.durationSeconds).reduce(0, +)

        self.summary = DashboardSummary(
            totalSeconds: total,
            productiveSeconds: productive,
            unproductiveSeconds: unproductive,
            idleSeconds: idle,
            sessionCount: timelineSessions.count
        )
    }
}
