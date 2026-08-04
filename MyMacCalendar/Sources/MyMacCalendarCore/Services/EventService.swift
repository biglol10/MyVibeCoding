import Foundation

public struct EventService {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func upcomingEvents(from startDate: Date, events: [CalendarEvent], limit: Int) -> [CalendarEvent] {
        guard limit > 0 else { return [] }
        let startOfDay = calendar.startOfDay(for: startDate)
        return events
            .filter { calendar.startOfDay(for: $0.endDate) >= startOfDay }
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.startDate < $1.startDate
            }
            .prefix(limit)
            .map { $0 }
    }

    public func upcomingOccurrences(from startDate: Date, events: [CalendarEvent], limit: Int, horizonDays: Int = 90) -> [EventOccurrence] {
        guard limit > 0 else { return [] }
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(byAdding: .day, value: horizonDays, to: start) ?? start
        let interval = DateInterval(start: start, end: end)
        let expander = RecurrenceExpander(calendar: calendar)

        return events
            .flatMap { expander.occurrences(for: $0, in: interval) }
            .filter { $0.endDate >= start }
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.startDate < $1.startDate
            }
            .prefix(limit)
            .map { $0 }
    }

    public func search(_ query: String, in events: [CalendarEvent]) -> [CalendarEvent] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.isEmpty == false else { return events }
        return events
            .filter { event in
                event.title.lowercased().contains(normalized) ||
                    event.notes.lowercased().contains(normalized)
            }
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.startDate < $1.startDate
            }
    }
}
