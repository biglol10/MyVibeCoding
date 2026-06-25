import Foundation

public struct EventDeletePlan: Equatable {
    public let eventID: UUID
    public let notificationIdentifiers: [String]
}

public struct EventService {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func upcomingEvents(from startDate: Date, events: [CalendarEvent], limit: Int) -> [CalendarEvent] {
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
        return events.filter { event in
            event.title.lowercased().contains(normalized) ||
            event.notes.lowercased().contains(normalized)
        }
    }

    public func deletePlan(for event: CalendarEvent) -> EventDeletePlan {
        let identifiers = event.notificationOffsetsDays.map { offset in
            "event-\(event.id.uuidString.lowercased())-offset-\(offset)"
        }
        return EventDeletePlan(eventID: event.id, notificationIdentifiers: identifiers)
    }
}
