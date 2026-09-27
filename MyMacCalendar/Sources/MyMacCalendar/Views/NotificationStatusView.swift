import AppKit
import SwiftUI
import MyMacCalendarCore

struct NotificationStatusView: View {
    @ObservedObject private var coordinator = AppNotificationCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(coordinator.status.message,
                  systemImage: coordinator.status.needsAttention ? "exclamationmark.triangle" : "bell")
                .font(.callout)
                .foregroundStyle(coordinator.status.needsAttention ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if coordinator.status == .permissionRequired {
                    Button("알림 허용") {
                        Task {
                            await coordinator.requestPermission()
                            NotificationCenter.default.post(name: .refreshCalendarNotifications, object: nil)
                        }
                    }
                }
                Button("시스템 알림 설정") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("다시 확인") {
                    NotificationCenter.default.post(name: .refreshCalendarNotifications, object: nil)
                }
            }
            .font(.caption)
        }
    }
}
