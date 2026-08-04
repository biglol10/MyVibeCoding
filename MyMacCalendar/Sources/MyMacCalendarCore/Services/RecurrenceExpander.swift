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
    private let calculator: EventRecurrenceCalculator

    public init(calendar: Calendar = .current) {
        self.calculator = EventRecurrenceCalculator(calendar: calendar)
    }

    public func occurrences(for event: CalendarEvent, in interval: DateInterval) -> [EventOccurrence] {
        calculator.occurrences(for: CalendarEventSnapshot(event: event), in: interval)
    }
}
