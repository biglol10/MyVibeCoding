import Foundation
@preconcurrency import UserNotifications

public enum NotificationAuthorizationState: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

public struct ScheduledNotificationRequest: Equatable, Sendable {
    public let identifier: String
    public let eventID: UUID
    public let title: String
    public let body: String
    public let fireDate: Date

    public init(identifier: String, eventID: UUID, title: String, body: String, fireDate: Date) {
        self.identifier = identifier
        self.eventID = eventID
        self.title = title
        self.body = body
        self.fireDate = fireDate
    }
}

@MainActor
public protocol NotificationClient: AnyObject {
    func authorizationState() async throws -> NotificationAuthorizationState
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async throws -> [String]
    func add(_ request: ScheduledNotificationRequest) async throws
    func removePending(identifiers: [String]) async
}

@MainActor
public final class SystemNotificationClient: NotificationClient {
    private let centerProvider: () -> UNUserNotificationCenter
    private let calendar: Calendar

    public init(
        centerProvider: @escaping () -> UNUserNotificationCenter = { .current() },
        calendar: Calendar = .current
    ) {
        self.centerProvider = centerProvider
        self.calendar = calendar
    }

    public func authorizationState() async throws -> NotificationAuthorizationState {
        let settings = await centerProvider().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    public func requestAuthorization() async throws -> Bool {
        try await centerProvider().requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func pendingIdentifiers() async throws -> [String] {
        await centerProvider().pendingNotificationRequests().map(\.identifier)
    }

    public func add(_ request: ScheduledNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: request.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let notificationRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )

        try await centerProvider().add(notificationRequest)
    }

    public func removePending(identifiers: [String]) async {
        guard identifiers.isEmpty == false else { return }
        centerProvider().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
