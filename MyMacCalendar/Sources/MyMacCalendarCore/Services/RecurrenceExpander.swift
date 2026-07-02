import Foundation

public struct EventOccurrence: Equatable {
    public let eventID: UUID
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let colorHex: String

    public var occurrenceID: String {
        "\(eventID.uuidString)-\(startDate.timeIntervalSinceReferenceDate)"
    }
}

public struct RecurrenceExpander {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func occurrences(for event: CalendarEvent, in interval: DateInterval) -> [EventOccurrence] {
        let durationDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: event.startDate), to: calendar.startOfDay(for: event.endDate)).day ?? 0
        var result: [EventOccurrence] = []
        let anchorDate = calendar.startOfDay(for: event.startDate)
        var cursor = anchorDate
        var occurrenceIndex = 0

        while cursor < interval.end {
            let occurrenceEnd = calendar.date(byAdding: .day, value: durationDays, to: cursor) ?? cursor
            if occurrenceEnd >= interval.start && cursor < interval.end {
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
            guard let next = occurrenceDate(anchorDate: anchorDate, recurrence: event.recurrence, occurrenceIndex: occurrenceIndex) else { break }
            if next <= cursor { break }
            cursor = next
        }

        return result
    }

    private func occurrenceDate(anchorDate: Date, recurrence: EventRecurrence, occurrenceIndex: Int) -> Date? {
        switch recurrence {
        case .none:
            return nil
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: occurrenceIndex, to: anchorDate)
        case .monthly:
            return dateByAddingMonths(occurrenceIndex, to: anchorDate)
        case .yearly:
            return dateByAddingYears(occurrenceIndex, to: anchorDate)
        }
    }

    private func dateByAddingMonths(_ months: Int, to anchorDate: Date) -> Date? {
        let anchorComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: anchorDate)
        guard let anchorMonthStart = calendar.date(from: DateComponents(year: anchorComponents.year, month: anchorComponents.month, day: 1)),
              let targetMonthStart = calendar.date(byAdding: .month, value: months, to: anchorMonthStart),
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
        let anchorComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: anchorDate)
        guard let year = anchorComponents.year,
              let month = anchorComponents.month,
              let day = anchorComponents.day,
              let targetMonthStart = calendar.date(from: DateComponents(year: year + years, month: month, day: 1)) else {
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
