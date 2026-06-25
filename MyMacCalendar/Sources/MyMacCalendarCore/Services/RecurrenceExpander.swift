import Foundation

public struct EventOccurrence: Equatable {
    public let eventID: UUID
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let colorHex: String
}

public struct RecurrenceExpander {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func occurrences(for event: CalendarEvent, in interval: DateInterval) -> [EventOccurrence] {
        let durationDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: event.startDate), to: calendar.startOfDay(for: event.endDate)).day ?? 0
        var result: [EventOccurrence] = []
        var cursor = calendar.startOfDay(for: event.startDate)

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
            guard let next = nextDate(after: cursor, recurrence: event.recurrence) else { break }
            if next <= cursor { break }
            cursor = next
        }

        return result
    }

    private func nextDate(after date: Date, recurrence: EventRecurrence) -> Date? {
        switch recurrence {
        case .none:
            return nil
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}
