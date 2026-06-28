import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case today
    case timeline
    case weekly
    case review
    case rules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "오늘 요약"
        case .timeline: return "타임라인"
        case .weekly: return "주간 리포트"
        case .review: return "미분류 검토"
        case .rules: return "분류 규칙"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "square.grid.2x2"
        case .timeline: return "clock"
        case .weekly: return "chart.bar"
        case .review: return "tray"
        case .rules: return "slider.horizontal.3"
        }
    }
}

struct AppShellView: View {
    @EnvironmentObject private var collector: NativeActivityCollectorService
    @State private var selection: NavigationItem = .today

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(NavigationItem.allCases) { item in
                    Button {
                        selection = item
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        selection == item ? Color.accentColor.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }

                Spacer()

                HStack(spacing: 8) {
                    Circle()
                        .fill(collector.pauseReason == nil && collector.isRunning ? .green : .gray)
                        .frame(width: 8, height: 8)
                    Text(collector.pauseReason == nil && collector.isRunning ? "Swift 수집 중" : "수집 일시중지")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
            }
            .padding(12)
            .frame(minWidth: 180, alignment: .topLeading)
            .navigationTitle("FlowPilot")
        } detail: {
            switch selection {
            case .today: TodayView()
            case .timeline: TimelineView()
            case .weekly: WeeklyReportView()
            case .review: ReviewView()
            case .rules: RulesView()
            }
        }
    }
}
