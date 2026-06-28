import FlowPilotNativeCore
import SwiftUI

struct WeeklyReportView: View {
    @EnvironmentObject private var store: FlowPilotReportStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                summaryGrid
                UsageBarChartView(title: "주간 사용량 차트", items: store.weeklyData.usageItems, limit: 8)
                usageList
            }
            .padding(28)
        }
        .navigationTitle("주간 리포트")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("최근 7일")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("주간 리포트")
                    .font(.largeTitle.bold())
            }
            Spacer()
            Text("\(store.weeklyData.summary.sessionCount)개 세션")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
    }

    private var summaryGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                metric("총 기록 시간", store.weeklyData.summary.totalSeconds)
                metric("생산적 사용", store.weeklyData.summary.productiveSeconds)
            }
            GridRow {
                metric("비생산 사용", store.weeklyData.summary.unproductiveSeconds)
                metric("유휴 시간", store.weeklyData.summary.idleSeconds)
            }
        }
    }

    private func metric(_ title: String, _ seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(DurationFormatting.compact(seconds: seconds))
                .font(.title.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    private var usageList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("앱과 사이트 리포트")
                .font(.title2.bold())
            ForEach(store.weeklyData.usageItems.prefix(20)) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.headline)
                        Text(item.ruleSource)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.category.koreanLabel)
                        .foregroundStyle(item.category.color)
                    Text(DurationFormatting.compact(seconds: item.durationSeconds))
                        .font(.headline)
                        .frame(width: 90, alignment: .trailing)
                }
                Divider()
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}
