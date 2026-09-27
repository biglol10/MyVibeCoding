import Foundation
import SwiftData

// Historical schema: keep these stored properties unchanged.
enum CalendarSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [CalendarEvent.self, HolidayRecord.self, AppSettings.self]
    }

    @Model
    final class CalendarEvent {
        @Attribute(.unique) var id: UUID
        var title: String
        var startDate: Date
        var endDate: Date
        var colorHex: String
        var categoryRaw: String = EventCategory.personal.rawValue
        var notes: String
        var recurrenceRaw: String
        var notificationOffsetsRaw: String
        var createdAt: Date
        var updatedAt: Date

        init(
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
            self.notificationOffsetsRaw = Self.encodeNotificationOffsets(notificationOffsetsDays)
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        var notificationOffsetsDays: [Int] {
            get { Self.decodeNotificationOffsets(notificationOffsetsRaw) }
            set { notificationOffsetsRaw = Self.encodeNotificationOffsets(newValue) }
        }

        var recurrence: EventRecurrence {
            get { EventRecurrence(rawValue: recurrenceRaw) ?? .none }
            set { recurrenceRaw = newValue.rawValue }
        }

        var category: EventCategory {
            get { EventCategory(rawValue: categoryRaw) ?? .personal }
            set {
                categoryRaw = newValue.rawValue
                colorHex = newValue.colorHex
            }
        }

        private static func encodeNotificationOffsets(_ offsets: [Int]) -> String {
            offsets
                .map(String.init)
                .joined(separator: ",")
        }

        private static func decodeNotificationOffsets(_ rawValue: String) -> [Int] {
            rawValue
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }

    @Model
    final class HolidayRecord {
        @Attribute(.unique) var id: UUID
        var date: Date
        var title: String
        var sourceRaw: String
        var providerKey: String
        var isHidden: Bool
        var year: Int
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            date: Date,
            title: String,
            source: HolidaySource,
            providerKey: String = "",
            isHidden: Bool = false,
            year: Int,
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.date = date
            self.title = title
            self.sourceRaw = source.rawValue
            self.providerKey = providerKey
            self.isHidden = isHidden
            self.year = year
            self.updatedAt = updatedAt
        }

        var source: HolidaySource {
            get { HolidaySource(rawValue: sourceRaw) ?? .manual }
            set { sourceRaw = newValue.rawValue }
        }
    }

    @Model
    final class AppSettings {
        @Attribute(.unique) var id: String
        var launchAtLogin: Bool
        var showMenuBar: Bool
        var floatingWidgetEnabled: Bool
        var floatingWidgetAlwaysOnTop: Bool
        var floatingWidgetOpacity: Double
        var floatingWidgetVisibleCount: Int
        var defaultReminderHour: Int
        var defaultReminderMinute: Int
        var theme: String
        var calendarDensity: String

        init(
            id: String = "default",
            launchAtLogin: Bool = false,
            showMenuBar: Bool = true,
            floatingWidgetEnabled: Bool = true,
            floatingWidgetAlwaysOnTop: Bool = true,
            floatingWidgetOpacity: Double = 0.96,
            floatingWidgetVisibleCount: Int = 5,
            defaultReminderHour: Int = 9,
            defaultReminderMinute: Int = 0,
            theme: String = "system",
            calendarDensity: String = "comfortable"
        ) {
            self.id = id
            self.launchAtLogin = launchAtLogin
            self.showMenuBar = showMenuBar
            self.floatingWidgetEnabled = floatingWidgetEnabled
            self.floatingWidgetAlwaysOnTop = floatingWidgetAlwaysOnTop
            self.floatingWidgetOpacity = floatingWidgetOpacity
            self.floatingWidgetVisibleCount = floatingWidgetVisibleCount
            self.defaultReminderHour = defaultReminderHour
            self.defaultReminderMinute = defaultReminderMinute
            self.theme = theme
            self.calendarDensity = calendarDensity
        }
    }
}
