import Foundation
import SwiftData

public enum EventRecurrence: String, Codable, CaseIterable, Identifiable {
    case none
    case weekly
    case monthly
    case yearly

    public var id: String { rawValue }
}

@Model
public final class CalendarEvent {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var colorHex: String
    public var notes: String
    public var recurrenceRaw: String
    public var notificationOffsetsDays: [Int]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        colorHex: String = "#4F7DFF",
        notes: String = "",
        recurrence: EventRecurrence = .none,
        notificationOffsetsDays: [Int] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.colorHex = colorHex
        self.notes = notes
        self.recurrenceRaw = recurrence.rawValue
        self.notificationOffsetsDays = notificationOffsetsDays
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var recurrence: EventRecurrence {
        get { EventRecurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }
}
