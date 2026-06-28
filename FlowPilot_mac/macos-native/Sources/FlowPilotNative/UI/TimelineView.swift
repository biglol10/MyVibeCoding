import FlowPilotNativeCore
import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: FlowPilotReportStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("타임라인")
                        .font(.largeTitle.bold())
                    Spacer()
                    Text("\(store.timelineSessions.count)개 세션")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                }

                ForEach(store.timelineSessions) { session in
                    HStack(alignment: .top, spacing: 14) {
                        Circle()
                            .fill(session.category.color)
                            .frame(width: 10, height: 10)
                            .padding(.top, 8)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(session.name).font(.headline)
                                Spacer()
                                Text(DurationFormatting.compact(seconds: session.durationSeconds))
                                    .font(.headline)
                            }
                            Text(session.title ?? session.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(session.category.koreanLabel)
                                .font(.caption)
                                .foregroundStyle(session.category.color)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    }
                }
            }
            .padding(28)
        }
    }
}
