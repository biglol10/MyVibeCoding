import MyMacCalendarCore

@MainActor
enum AppNotificationCoordinator {
    static let shared = NotificationUpdateCoordinator(client: SystemNotificationClient())
}
