import Foundation
import SwiftData

public enum EventRecurrence: String, Codable, CaseIterable, Identifiable {
    case none
    case weekly
    case monthly
    case yearly

    public var id: String { rawValue }
}

public enum EventCategory: String, Codable, CaseIterable, Identifiable {
    case personal
    case work
    case family
    case payment
    case health
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .personal:
            return "개인"
        case .work:
            return "업무"
        case .family:
            return "가족"
        case .payment:
            return "결제"
        case .health:
            return "건강"
        case .other:
            return "기타"
        }
    }

    public var colorHex: String {
        switch self {
        case .personal:
            return "#4F7DFF"
        case .work:
            return "#D66AF5"
        case .family:
            return "#34C759"
        case .payment:
            return "#FF9500"
        case .health:
            return "#FF453A"
        case .other:
            return "#8E8E93"
        }
    }
}

@Model
public final class CalendarEvent {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var colorHex: String
    public var categoryRaw: String = EventCategory.personal.rawValue
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
        colorHex: String = EventCategory.personal.colorHex,
        category: EventCategory = .personal,
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
        self.categoryRaw = category.rawValue
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

    public var category: EventCategory {
        get { EventCategory(rawValue: categoryRaw) ?? .personal }
        set {
            categoryRaw = newValue.rawValue
            colorHex = newValue.colorHex
        }
    }
}
