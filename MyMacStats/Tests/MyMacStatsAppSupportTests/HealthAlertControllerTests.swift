import XCTest
import MyMacStatsCore
@testable import MyMacStatsAppSupport

@MainActor
final class HealthAlertControllerTests: XCTestCase {
    func testMemoryCriticalMustPersistBeforeNotificationIsDelivered() async {
        let notifier = RecordingHealthAlertNotifier()
        let controller = HealthAlertController(
            notifier: notifier,
            sustainedCriticalSeconds: 30
        )

        await controller.observe(snapshot: snapshot(health: .critical, at: 0))
        await controller.observe(snapshot: snapshot(health: .critical, at: 29))
        XCTAssertEqual(notifier.deliveredAlerts, [])

        await controller.observe(snapshot: snapshot(health: .critical, at: 30))

        XCTAssertEqual(notifier.authorizationRequestCount, 1)
        XCTAssertEqual(notifier.deliveredAlerts.map(\.kind), [.memoryCritical])
    }

    func testMemoryCriticalNotificationResetsAfterRecovery() async {
        let notifier = RecordingHealthAlertNotifier()
        let controller = HealthAlertController(
            notifier: notifier,
            sustainedCriticalSeconds: 30
        )

        await controller.observe(snapshot: snapshot(health: .critical, at: 0))
        await controller.observe(snapshot: snapshot(health: .critical, at: 31))
        await controller.observe(snapshot: snapshot(health: .normal, at: 40))
        await controller.observe(snapshot: snapshot(health: .critical, at: 50))
        await controller.observe(snapshot: snapshot(health: .critical, at: 81))

        XCTAssertEqual(notifier.deliveredAlerts.map(\.kind), [.memoryCritical, .memoryCritical])
    }

    private func snapshot(health: HealthState, at seconds: TimeInterval) -> SystemMetricsSnapshot {
        let date = Date(timeIntervalSince1970: seconds)
        return SystemMetricsSnapshot(
            summaries: [
                MetricSummary(
                    kind: .memory,
                    title: "RAM",
                    valueText: "15G / 16G",
                    detailText: "Free 500 MB",
                    health: health,
                    updatedAt: date
                )
            ],
            cpu: nil,
            memory: nil,
            disk: nil,
            network: nil,
            battery: nil,
            processes: [],
            cpuHistory: [],
            updatedAt: date
        )
    }
}

@MainActor
private final class RecordingHealthAlertNotifier: HealthAlertNotifying {
    private(set) var authorizationRequestCount = 0
    private(set) var deliveredAlerts: [HealthAlert] = []

    func requestAuthorization() async {
        authorizationRequestCount += 1
    }

    func deliver(_ alert: HealthAlert) async {
        deliveredAlerts.append(alert)
    }
}
