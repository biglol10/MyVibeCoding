import AppKit
import FlowPilotNativeCore
import SwiftUI

@main
struct FlowPilotNativeApp: App {
    @StateObject private var browserBridge: NativeBrowserBridgeService
    @StateObject private var collector: NativeActivityCollectorService
    @StateObject private var reportStore = FlowPilotReportStore()

    init() {
        let databaseURL = FlowPilotReportStore.defaultDatabaseURL()
        let reportStore = FlowPilotReportStore(databaseURL: databaseURL)
        _reportStore = StateObject(wrappedValue: reportStore)
        _browserBridge = StateObject(wrappedValue: NativeBrowserBridgeService(databaseURL: databaseURL))
        _collector = StateObject(
            wrappedValue: NativeActivityCollectorService(databaseURL: databaseURL) {
                reportStore.refresh()
            }
        )
    }

    var body: some Scene {
        WindowGroup("FlowPilot") {
            AppShellView()
                .environmentObject(reportStore)
                .environmentObject(collector)
                .environmentObject(browserBridge)
                .frame(minWidth: 960, minHeight: 680)
                .onAppear {
                    browserBridge.start()
                    collector.start()
                }
        }

        MenuBarExtra("FlowPilot", systemImage: "paperplane.circle.fill") {
            Text("오늘 기록 \(DurationFormatting.compact(seconds: reportStore.summary.totalSeconds))")
            Text("생산적 \(DurationFormatting.compact(seconds: reportStore.summary.productiveSeconds))")
            Text(collector.pauseReason ?? (collector.isRunning ? "Swift 수집 중" : "수집 중지"))
            Text(browserBridge.isRunning ? "브라우저 브리지 실행 중" : "브라우저 브리지 대기")
            Divider()
            Button("새로고침") {
                reportStore.refresh()
            }
            Button("FlowPilot 열기") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("종료") {
                NSApp.terminate(nil)
            }
        }
    }
}
