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
    private var deliveryTask: Task<Void, Never>?

    deinit { deliveryTask?.cancel() }

    public init(
        notifier: HealthAlertNotifying = UserNotificationHealthAlertNotifier(),
        sustainedCriticalSeconds: TimeInterval = 30
    ) {
        self.notifier = notifier
        self.sustainedCriticalSeconds = sustainedCriticalSeconds
    }

    public func observe(snapshot: SystemMetricsSnapshot) async {
        await submit(snapshot: snapshot)?.value
    }

    /// Queue notification work without delaying metric sampling or termination validation.
    @discardableResult
    public func submit(snapshot: SystemMetricsSnapshot) -> Task<Void, Never>? {
        guard snapshot.summary(for: .memory)?.health == .critical else {
            memoryCriticalStartedAt = nil
            didSendMemoryCriticalAlert = false
            return nil
        }

        let criticalStartedAt = memoryCriticalStartedAt ?? snapshot.updatedAt
        memoryCriticalStartedAt = criticalStartedAt

        guard !didSendMemoryCriticalAlert,
              deliveryTask == nil,
              snapshot.updatedAt.timeIntervalSince(criticalStartedAt) >= sustainedCriticalSeconds
        else {
            return nil
        }

        didSendMemoryCriticalAlert = true
        let needsAuthorization = !didRequestAuthorization
        didRequestAuthorization = true
        let notifier = notifier
        let duration = Int(sustainedCriticalSeconds)
        deliveryTask = Task { [weak self] in
            defer { self?.deliveryTask = nil }
            if needsAuthorization { await notifier.requestAuthorization() }
            guard !Task.isCancelled, self?.memoryCriticalStartedAt == criticalStartedAt else { return }
            await notifier.deliver(
                HealthAlert(
                    kind: .memoryCritical,
                    title: "MyMacStats RAM Critical",
                    message: "RAM has stayed critical for \(duration) seconds. Open MyMacStats to inspect high-memory apps."
                )
            )
        }
        return deliveryTask
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
