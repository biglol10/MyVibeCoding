import FlowPilotNativeCore
import SwiftUI

struct UsageBarChartView: View {
    let title: String
    let items: [UsageItem]
    let limit: Int

    private var rows: [UsageChartScaling.Row] {
        UsageChartScaling.rows(items: items, limit: limit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.bold())

            if rows.isEmpty {
                Text("표시할 사용 기록이 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
            } else {
                VStack(spacing: 12) {
                    ForEach(rows, id: \.id) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(row.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(DurationFormatting.compact(seconds: row.durationSeconds))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.quaternary)
                                    Capsule()
                                        .fill(row.category.color)
                                        .frame(width: max(2, proxy.size.width * row.relativeWidth))
                                }
                            }
                            .frame(height: 10)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}
