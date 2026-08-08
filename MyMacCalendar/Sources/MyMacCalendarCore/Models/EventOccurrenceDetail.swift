import Foundation

public struct EventOccurrenceDetail: Equatable, Sendable {
    public let eventID: UUID
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let colorHex: String
    public let notes: String
    public let recurrence: EventRecurrence
    public let notificationOffsetsDays: [Int]

    public init(event: CalendarEvent, occurrence: EventOccurrence) {
        self.eventID = event.id
        self.title = event.title
        self.startDate = occurrence.startDate
        self.endDate = occurrence.endDate
        self.colorHex = event.colorHex
        self.notes = event.notes
        self.recurrence = event.recurrence
        self.notificationOffsetsDays = event.notificationOffsetsDays
    }
}
