import AppKit
import FlowPilotNativeCore
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var browserBridge: NativeBrowserBridgeService
    @EnvironmentObject private var store: FlowPilotReportStore
    @EnvironmentObject private var collector: NativeActivityCollectorService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                permissionNotice
                collectorPauseNotice
                collectorError
                browserBridgeError
                summaryGrid
                UsageBarChartView(title: "사용량 차트", items: store.usageItems, limit: 6)
                usageTable
            }
            .padding(28)
        }
        .navigationTitle("오늘 요약")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("활동 분석")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("오늘 요약")
                    .font(.largeTitle.bold())
                Text(store.dataSourceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(store.summary.sessionCount)개 세션")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    private var permissionNotice: some View {
        if !MacPermissionStatus.accessibilityTrusted || !MacPermissionStatus.screenRecordingLikelyAllowed {
            VStack(alignment: .leading, spacing: 8) {
                Text("macOS 권한 설정이 필요할 수 있습니다")
                    .font(.headline)
                Text("앱 이름과 창 제목을 더 정확히 기록하려면 시스템 설정 > 개인정보 보호 및 보안에서 FlowPilot의 손쉬운 사용 및 화면 기록 권한을 허용해 주세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Safari 탭 도메인을 기록하려면 macOS가 표시하는 자동화 권한에서 FlowPilot이 Safari를 제어하도록 허용해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("FlowPilot은 화면 이미지를 저장하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("손쉬운 사용 열기") {
                        NSWorkspace.shared.open(MacPermissionSettings.accessibility.url)
                    }
                    Button("화면 기록 열기") {
                        NSWorkspace.shared.open(MacPermissionSettings.screenRecording.url)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.yellow.opacity(0.35)))
        }
    }

    @ViewBuilder
    private var collectorPauseNotice: some View {
        if let pauseReason = collector.pauseReason {
            Text(pauseReason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var browserBridgeError: some View {
        if let error = browserBridge.lastError {
            Text("브라우저 브리지: \(error)")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var collectorError: some View {
        if let error = collector.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var summaryGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                metric("총 기록 시간", store.summary.totalSeconds)
                metric("생산적 사용", store.summary.productiveSeconds)
            }
            GridRow {
                metric("비생산 사용", store.summary.unproductiveSeconds)
                metric("유휴 시간", store.summary.idleSeconds)
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

    private var usageTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("상위 사용 항목")
                .font(.title2.bold())
            ForEach(store.usageItems) { item in
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
                        .frame(width: 80, alignment: .trailing)
                }
                Divider()
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}
