import Foundation

public struct NotificationPlan: Equatable, Sendable {
    public let identifier: String
    public let eventID: UUID
    public let title: String
    public let occurrenceDate: Date
    public let fireDate: Date
    public let offsetDays: Int
}

public struct NotificationPlanner {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func plans(
        for events: [CalendarEventSnapshot],
        defaultHour: Int,
        defaultMinute: Int,
        now: Date = Date(),
        horizonDays: Int = 90,
        maximumPlans: Int = 64,
        batchID: String
    ) -> [NotificationPlan] {
        guard horizonDays >= 0, maximumPlans > 0 else { return [] }
        guard let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: now) else { return [] }
        let hour = SettingsValidation.reminderHour(defaultHour)
        let minute = SettingsValidation.reminderMinute(defaultMinute)
        let recurrenceCalculator = EventRecurrenceCalculator(calendar: calendar)
        var result: [NotificationPlan] = []

        for event in events {
            let offsets = Array(Set(event.notificationOffsetsDays.filter { $0 >= 0 })).sorted(by: >)
            guard offsets.isEmpty == false else { continue }
            let maximumOffset = offsets.max() ?? 0
            let expansionStart = calendar.startOfDay(for: now)
            let (horizonWithOffset, offsetOverflowed) = horizonDays.addingReportingOverflow(maximumOffset)
            let (expansionDays, paddingOverflowed) = horizonWithOffset.addingReportingOverflow(1)
            guard offsetOverflowed == false, paddingOverflowed == false else { continue }
            guard let expansionEnd = calendar.date(
                byAdding: .day,
                value: expansionDays,
                to: expansionStart
            ) else {
                continue
            }
            let occurrences = recurrenceCalculator.occurrences(
                for: event,
                in: DateInterval(start: expansionStart, end: expansionEnd)
            )

            for occurrence in occurrences {
                for offset in offsets {
                    guard let reminderDay = calendar.date(byAdding: .day, value: -offset, to: occurrence.startDate) else {
                        continue
                    }
                    var components = calendar.dateComponents([.year, .month, .day], from: reminderDay)
                    components.hour = hour
                    components.minute = minute
                    guard let fireDate = calendar.date(from: components),
                          fireDate > now,
                          fireDate <= horizonEnd else {
                        continue
                    }

                    result.append(
                        NotificationPlan(
                            identifier: identifier(
                                eventID: event.id,
                                occurrenceDate: occurrence.startDate,
                                offset: offset,
                                batchID: batchID
                            ),
                            eventID: event.id,
                            title: event.title,
                            occurrenceDate: occurrence.startDate,
                            fireDate: fireDate,
                            offsetDays: offset
                        )
                    )
                }
            }
        }

        return Array(
            result.sorted {
                if $0.fireDate == $1.fireDate {
                    return $0.identifier < $1.identifier
                }
                return $0.fireDate < $1.fireDate
            }.prefix(maximumPlans)
        )
    }

    public func plans(
        for event: CalendarEvent,
        defaultHour: Int,
        defaultMinute: Int,
        now: Date = Date()
    ) -> [NotificationPlan] {
        plans(
            for: [CalendarEventSnapshot(event: event)],
            defaultHour: defaultHour,
            defaultMinute: defaultMinute,
            now: now,
            batchID: "legacy"
        )
    }

    private func identifier(eventID: UUID, occurrenceDate: Date, offset: Int, batchID: String) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: occurrenceDate)
        let occurrenceToken = String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        let safeBatchID = batchID
            .lowercased()
            .map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }
        return "event-\(eventID.uuidString.lowercased())-occurrence-\(occurrenceToken)-offset-\(offset)-batch-\(String(safeBatchID))"
    }
}
