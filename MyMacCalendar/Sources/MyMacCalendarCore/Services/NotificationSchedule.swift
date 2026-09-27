import Foundation

public struct NotificationSchedule {
    public let requests: [ScheduledNotificationRequest]
    public let scheduledReminderCount: Int
    public let deferredReminderCount: Int
    public let eventIDsByRequest: [String: Set<UUID>]

    public init(plans: [NotificationPlan], maximumRequests: Int, batchID: String) {
        // One OS request per fire time prevents simultaneous reminders from
        // competing for the finite pending-request budget.
        let groups = Dictionary(grouping: plans, by: \.fireDate)
        let dates = groups.keys.sorted().prefix(max(0, maximumRequests))
        var requests: [ScheduledNotificationRequest] = []
        var members: [String: Set<UUID>] = [:]
        var scheduled = 0
        for date in dates {
            let group = groups[date, default: []].sorted { $0.identifier < $1.identifier }
            guard let first = group.first else { continue }
            let body: String
            if group.count == 1 {
                body = first.offsetDays == 0 ? "오늘 일정입니다." : "\(first.offsetDays)일 전 알림입니다."
            } else {
                body = group.map { "\($0.title) (\($0.offsetDays == 0 ? "당일" : "\($0.offsetDays)일 전"))" }
                    .joined(separator: " · ")
            }
            let request = ScheduledNotificationRequest(
                identifier: group.count == 1 ? first.identifier :
                    "event-\(first.eventID.uuidString.lowercased())-group-\(Int(date.timeIntervalSince1970))-batch-\(batchID)",
                eventID: first.eventID,
                title: group.count == 1 ? first.title : "일정 알림 \(group.count)개",
                body: body,
                fireDate: date
            )
            requests.append(request)
            members[request.identifier] = Set(group.map(\.eventID))
            scheduled += group.count
        }
        self.requests = requests
        self.scheduledReminderCount = scheduled
        self.deferredReminderCount = plans.count - scheduled
        self.eventIDsByRequest = members
    }
}

public enum NotificationRefreshStatus: Equatable {
    case idle
    case permissionRequired
    case denied
    case scheduled(reminders: Int, requests: Int, deferred: Int)
    case failed

    public var needsAttention: Bool {
        switch self {
        case .denied, .failed: return true
        case .scheduled(_, _, let deferred): return deferred > 0
        default: return false
        }
    }

    public var message: String {
        switch self {
        case .idle: return "알림 상태를 확인하고 있습니다."
        case .permissionRequired: return "알림을 받으려면 macOS 알림 권한을 허용해 주세요."
        case .denied: return "알림 권한이 꺼져 있어 일정 알림을 받을 수 없습니다."
        case .failed: return "일정은 저장되어 있지만 일부 알림을 갱신하지 못했습니다. 다시 시도해 주세요."
        case .scheduled(let reminders, _, let deferred):
            if deferred > 0 {
                return "알림 \(reminders)개 예약 · \(deferred)개 대기. 대기 알림은 앱 실행 중 순차 예약됩니다."
            }
            return reminders == 0 ? "향후 90일 안에 예약할 알림이 없습니다." : "알림 \(reminders)개 예약됨 · 같은 시각의 알림은 함께 전달됩니다."
        }
    }
}
