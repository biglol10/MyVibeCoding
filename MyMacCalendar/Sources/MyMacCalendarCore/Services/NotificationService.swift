import Foundation
import UserNotifications

public struct NotificationPlan: Equatable {
    public let identifier: String
    public let eventID: UUID
    public let title: String
    public let fireDate: Date
    public let offsetDays: Int
}

public struct NotificationPlanner {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func plans(for event: CalendarEvent, defaultHour: Int, defaultMinute: Int, now: Date = Date()) -> [NotificationPlan] {
        event.notificationOffsetsDays
            .sorted(by: >)
            .compactMap { offset in
                guard let reminderDay = calendar.date(byAdding: .day, value: -offset, to: event.startDate) else { return nil }
                let dayComponents = calendar.dateComponents([.year, .month, .day], from: reminderDay)
                let reminderComponents = DateComponents(
                    year: dayComponents.year,
                    month: dayComponents.month,
                    day: dayComponents.day,
                    hour: defaultHour,
                    minute: defaultMinute
                )
                guard let fireDate = calendar.date(from: reminderComponents) else { return nil }
                guard fireDate > now else { return nil }
                return NotificationPlan(
                    identifier: "event-\(event.id.uuidString.lowercased())-offset-\(offset)",
                    eventID: event.id,
                    title: event.title,
                    fireDate: fireDate,
                    offsetDays: offset
                )
            }
    }
}

public final class NotificationService {
    private let center: UNUserNotificationCenter
    private let planner: NotificationPlanner

    public init(center: UNUserNotificationCenter = .current(), planner: NotificationPlanner = NotificationPlanner()) {
        self.center = center
        self.planner = planner
    }

    public func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    public func schedule(event: CalendarEvent, defaultHour: Int, defaultMinute: Int) {
        let plans = planner.plans(for: event, defaultHour: defaultHour, defaultMinute: defaultMinute)
        let identifiers = event.notificationOffsetsDays.map { offset in
            "event-\(event.id.uuidString.lowercased())-offset-\(offset)"
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.offsetDays == 0 ? "오늘 일정입니다." : "\(plan.offsetDays)일 전 알림입니다."
            content.sound = .default

            let triggerComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
            center.add(request) { error in
                if let error {
                    NSLog("Failed to schedule notification \(plan.identifier): \(error)")
                }
            }
        }
    }

    public func cancel(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
