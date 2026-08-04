import Foundation
import SwiftData

enum CalendarSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
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
        var notes: String
        var recurrenceRaw: String
        var notificationOffsetsDays: [Int]
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            title: String,
            startDate: Date,
            endDate: Date,
            colorHex: String = "#4F7DFF",
            notes: String = "",
            recurrenceRaw: String = EventRecurrence.none.rawValue,
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
            self.recurrenceRaw = recurrenceRaw
            self.notificationOffsetsDays = notificationOffsetsDays
            self.createdAt = createdAt
            self.updatedAt = updatedAt
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
            sourceRaw: String,
            providerKey: String = "",
            isHidden: Bool = false,
            year: Int,
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.date = date
            self.title = title
            self.sourceRaw = sourceRaw
            self.providerKey = providerKey
            self.isHidden = isHidden
            self.year = year
            self.updatedAt = updatedAt
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

enum CalendarSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
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
        var notificationOffsetsDays: [Int]
        var notificationOffsetsRaw: String = ""
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            title: String,
            startDate: Date,
            endDate: Date,
            colorHex: String = "#4F7DFF",
            categoryRaw: String = EventCategory.personal.rawValue,
            notes: String = "",
            recurrenceRaw: String = EventRecurrence.none.rawValue,
            notificationOffsetsDays: [Int] = [],
            notificationOffsetsRaw: String = "",
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.startDate = startDate
            self.endDate = endDate
            self.colorHex = colorHex
            self.categoryRaw = categoryRaw
            self.notes = notes
            self.recurrenceRaw = recurrenceRaw
            self.notificationOffsetsDays = notificationOffsetsDays
            self.notificationOffsetsRaw = notificationOffsetsRaw
            self.createdAt = createdAt
            self.updatedAt = updatedAt
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
            sourceRaw: String,
            providerKey: String = "",
            isHidden: Bool = false,
            year: Int,
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.date = date
            self.title = title
            self.sourceRaw = sourceRaw
            self.providerKey = providerKey
            self.isHidden = isHidden
            self.year = year
            self.updatedAt = updatedAt
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

enum CalendarSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [CalendarEvent.self, HolidayRecord.self, AppSettings.self]
    }
}

enum CalendarSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CalendarSchemaV1.self, CalendarSchemaV2.self, CalendarSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            MigrationStage.custom(
                fromVersion: CalendarSchemaV1.self,
                toVersion: CalendarSchemaV2.self,
                willMigrate: nil,
                didMigrate: { context in
                    let events = try context.fetch(FetchDescriptor<CalendarSchemaV2.CalendarEvent>())
                    for event in events {
                        event.notificationOffsetsRaw = event.notificationOffsetsDays
                            .map(String.init)
                            .joined(separator: ",")
                    }
                    try PersistenceTransaction.save(context: context)
                }
            ),
            MigrationStage.lightweight(
                fromVersion: CalendarSchemaV2.self,
                toVersion: CalendarSchemaV3.self
            )
        ]
    }
}
