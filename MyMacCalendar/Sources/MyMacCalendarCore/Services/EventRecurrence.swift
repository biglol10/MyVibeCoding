import Foundation

public struct CalendarEventSnapshot: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let colorHex: String
    public let recurrence: EventRecurrence
    public let notificationOffsetsDays: [Int]

    public init(
        id: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        colorHex: String,
        recurrence: EventRecurrence,
        notificationOffsetsDays: [Int]
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.colorHex = colorHex
        self.recurrence = recurrence
        self.notificationOffsetsDays = notificationOffsetsDays
    }

    public init(event: CalendarEvent) {
        self.init(
            id: event.id,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            colorHex: event.colorHex,
            recurrence: event.recurrence,
            notificationOffsetsDays: event.notificationOffsetsDays
        )
    }
}

public struct EventRecurrenceCalculator {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func occurrences(for event: CalendarEventSnapshot, in interval: DateInterval) -> [EventOccurrence] {
        let anchorDate = calendar.startOfDay(for: event.startDate)
        let durationDays = max(
            0,
            calendar.dateComponents(
                [.day],
                from: anchorDate,
                to: calendar.startOfDay(for: max(event.endDate, event.startDate))
            ).day ?? 0
        )
        var occurrenceIndex = firstOccurrenceIndex(for: event, near: interval.start)
        guard var cursor = occurrenceDate(anchorDate: anchorDate, recurrence: event.recurrence, occurrenceIndex: occurrenceIndex) else {
            return []
        }
        var result: [EventOccurrence] = []

        while cursor < interval.end {
            let occurrenceEnd = calendar.date(byAdding: .day, value: durationDays, to: cursor) ?? cursor
            if occurrenceEnd >= interval.start {
                result.append(
                    EventOccurrence(
                        eventID: event.id,
                        title: event.title,
                        startDate: cursor,
                        endDate: occurrenceEnd,
                        colorHex: event.colorHex
                    )
                )
            }

            guard event.recurrence != .none else { break }
            occurrenceIndex += 1
            guard let next = occurrenceDate(
                anchorDate: anchorDate,
                recurrence: event.recurrence,
                occurrenceIndex: occurrenceIndex
            ), next > cursor else {
                break
            }
            cursor = next
        }

        return result
    }

    public func firstOccurrenceIndex(for event: CalendarEventSnapshot, near date: Date) -> Int {
        let anchor = calendar.startOfDay(for: event.startDate)
        let durationDays = max(
            0,
            calendar.dateComponents(
                [.day],
                from: anchor,
                to: calendar.startOfDay(for: max(event.endDate, event.startDate))
            ).day ?? 0
        )
        let searchDate = calendar.date(byAdding: .day, value: -durationDays, to: date) ?? date
        guard searchDate > anchor else { return 0 }

        switch event.recurrence {
        case .none:
            return 0
        case .weekly:
            let days = calendar.dateComponents([.day], from: anchor, to: searchDate).day ?? 0
            return max(0, days / 7)
        case .monthly:
            let anchorComponents = calendar.dateComponents([.year, .month], from: anchor)
            let targetComponents = calendar.dateComponents([.year, .month], from: searchDate)
            guard let anchorYear = anchorComponents.year,
                  let anchorMonth = anchorComponents.month,
                  let targetYear = targetComponents.year,
                  let targetMonth = targetComponents.month else {
                return 0
            }
            return max(0, ((targetYear - anchorYear) * 12 + targetMonth - anchorMonth) - 1)
        case .yearly:
            let anchorYear = calendar.component(.year, from: anchor)
            let targetYear = calendar.component(.year, from: searchDate)
            return max(0, targetYear - anchorYear - 1)
        }
    }

    private func occurrenceDate(anchorDate: Date, recurrence: EventRecurrence, occurrenceIndex: Int) -> Date? {
        guard occurrenceIndex > 0 else { return anchorDate }
        switch recurrence {
        case .none:
            return anchorDate
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: occurrenceIndex, to: anchorDate)
        case .monthly:
            return dateByAddingMonths(occurrenceIndex, to: anchorDate)
        case .yearly:
            return dateByAddingYears(occurrenceIndex, to: anchorDate)
        }
    }

    private func dateByAddingMonths(_ months: Int, to anchorDate: Date) -> Date? {
        let anchorComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: anchorDate
        )
        guard let anchorMonthStart = calendar.date(
            from: DateComponents(year: anchorComponents.year, month: anchorComponents.month, day: 1)
        ), let targetMonthStart = calendar.date(byAdding: .month, value: months, to: anchorMonthStart),
           let day = anchorComponents.day else {
            return nil
        }

        var targetComponents = calendar.dateComponents([.year, .month], from: targetMonthStart)
        targetComponents.day = min(day, lastDayOfMonth(for: targetMonthStart))
        targetComponents.hour = anchorComponents.hour
        targetComponents.minute = anchorComponents.minute
        targetComponents.second = anchorComponents.second
        targetComponents.nanosecond = anchorComponents.nanosecond
        return calendar.date(from: targetComponents)
    }

    private func dateByAddingYears(_ years: Int, to anchorDate: Date) -> Date? {
        let anchorComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: anchorDate
        )
        guard let year = anchorComponents.year,
              let month = anchorComponents.month,
              let day = anchorComponents.day,
              let targetMonthStart = calendar.date(
                from: DateComponents(year: year + years, month: month, day: 1)
              ) else {
            return nil
        }

        var targetComponents = DateComponents()
        targetComponents.year = year + years
        targetComponents.month = month
        targetComponents.day = min(day, lastDayOfMonth(for: targetMonthStart))
        targetComponents.hour = anchorComponents.hour
        targetComponents.minute = anchorComponents.minute
        targetComponents.second = anchorComponents.second
        targetComponents.nanosecond = anchorComponents.nanosecond
        return calendar.date(from: targetComponents)
    }

    private func lastDayOfMonth(for date: Date) -> Int {
        calendar.range(of: .day, in: .month, for: date)?.count ?? 31
    }
}
