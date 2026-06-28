import FlowPilotNativeCore
import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var store: FlowPilotReportStore
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                if store.uncategorizedItems.isEmpty {
                    PlaceholderScreen(
                        title: "검토할 항목 없음",
                        systemImage: "checkmark.circle",
                        description: "오늘 기록된 항목은 모두 분류 규칙이 적용되어 있습니다."
                    )
                    .frame(minHeight: 360)
                } else {
                    reviewList
                }
            }
            .padding(28)
        }
        .navigationTitle("미분류 검토")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("오늘")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("미분류 검토")
                    .font(.largeTitle.bold())
            }
            Spacer()
            Text("\(store.uncategorizedItems.count)개 항목")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
    }

    private var reviewList: some View {
        VStack(spacing: 0) {
            ForEach(store.uncategorizedItems) { item in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.headline)
                        Text("\(item.ruleType.koreanLabel) · \(item.sessionCount)개 세션")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(DurationFormatting.compact(seconds: item.durationSeconds))
                        .font(.headline)
                        .frame(width: 80, alignment: .trailing)
                    quickButton("생산적", item, .productive)
                    quickButton("비생산", item, .unproductive)
                    quickButton("중립", item, .neutral)
                    quickButton("제외", item, .ignored)
                }
                .padding()
                Divider()
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    private func quickButton(
        _ title: String,
        _ item: UncategorizedItem,
        _ category: ActivityCategory
    ) -> some View {
        Button(title) {
            do {
                try store.saveRule(
                    ruleType: item.ruleType,
                    pattern: item.pattern,
                    category: category,
                    name: item.name
                )
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .buttonStyle(.bordered)
    }
}
