import Foundation
import MyMacStatsCore
@preconcurrency import UserNotifications

public enum HealthAlertKind: Equatable, Sendable {
    case memoryCritical
}

public struct HealthAlert: Equatable, Sendable {
    public let kind: HealthAlertKind
    public let title: String
    public let message: String

    public init(kind: HealthAlertKind, title: String, message: String) {
        self.kind = kind
        self.title = title
        self.message = message
    }
}

@MainActor
public protocol HealthAlertNotifying: AnyObject {
    func requestAuthorization() async
    func deliver(_ alert: HealthAlert) async
}

@MainActor
public final class HealthAlertController {
    private let notifier: HealthAlertNotifying
    private let sustainedCriticalSeconds: TimeInterval
    private var memoryCriticalStartedAt: Date?
    private var didSendMemoryCriticalAlert = false
    private var didRequestAuthorization = false

    public init(
        notifier: HealthAlertNotifying = UserNotificationHealthAlertNotifier(),
        sustainedCriticalSeconds: TimeInterval = 30
    ) {
        self.notifier = notifier
        self.sustainedCriticalSeconds = sustainedCriticalSeconds
    }

    public func observe(snapshot: SystemMetricsSnapshot) async {
        guard snapshot.summary(for: .memory)?.health == .critical else {
            memoryCriticalStartedAt = nil
            didSendMemoryCriticalAlert = false
            return
        }

        let criticalStartedAt = memoryCriticalStartedAt ?? snapshot.updatedAt
        memoryCriticalStartedAt = criticalStartedAt

        guard !didSendMemoryCriticalAlert,
              snapshot.updatedAt.timeIntervalSince(criticalStartedAt) >= sustainedCriticalSeconds
        else {
            return
        }

        await ensureAuthorization()
        await notifier.deliver(
            HealthAlert(
                kind: .memoryCritical,
                title: "MyMacStats RAM Critical",
                message: "RAM has stayed critical for 30 seconds. Open MyMacStats to inspect high-memory apps."
            )
        )
        didSendMemoryCriticalAlert = true
    }

    private func ensureAuthorization() async {
        guard !didRequestAuthorization else { return }
        await notifier.requestAuthorization()
        didRequestAuthorization = true
    }
}

@MainActor
public final class UserNotificationHealthAlertNotifier: HealthAlertNotifying {
    private let centerProvider: () -> UNUserNotificationCenter

    public init(centerProvider: @escaping () -> UNUserNotificationCenter = { .current() }) {
        self.centerProvider = centerProvider
    }

    public func requestAuthorization() async {
        _ = try? await centerProvider().requestAuthorization(options: [.alert, .sound])
    }

    public func deliver(_ alert: HealthAlert) async {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "com.local.MyMacStats.\(alert.kind).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        try? await centerProvider().add(request)
    }
}
