import Foundation
import SwiftData
import XCTest
@testable import MyMacCalendarCore

@MainActor
final class CalendarMigrationTests: XCTestCase {
    func testCategorizedArrayLegacyStoreMigratesWithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacCalendarCategorizedLegacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let originalURL = directory.appendingPathComponent("legacy.store")
        let copyURL = directory.appendingPathComponent("migration-copy.store")
        let eventID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let legacy = try makeCategorizedLegacyContainer(at: originalURL)
        legacy.mainContext.insert(
            CategorizedArrayLegacySchema.CalendarEvent(
                id: eventID,
                title: "Categorized legacy event",
                startDate: startDate,
                endDate: startDate,
                colorHex: EventCategory.work.colorHex,
                categoryRaw: EventCategory.work.rawValue,
                notes: "Legacy notes",
                recurrenceRaw: EventRecurrence.monthly.rawValue,
                notificationOffsetsDays: [7, 1, 0]
            )
        )
        legacy.mainContext.insert(
            CategorizedArrayLegacySchema.AppSettings(
                floatingWidgetVisibleCount: 6,
                defaultReminderHour: 8,
                defaultReminderMinute: 45
            )
        )
        try legacy.mainContext.save()
        try copyStoreFamily(from: originalURL, to: copyURL)

        let migrated = try CalendarStore.makeContainer(at: copyURL)
        let events = try migrated.mainContext.fetch(FetchDescriptor<CalendarEvent>())
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(event.id, eventID)
        XCTAssertEqual(event.category, .work)
        XCTAssertEqual(event.recurrence, .monthly)
        XCTAssertEqual(event.notificationOffsetsDays, [7, 1, 0])

        let settings = try migrated.mainContext.fetch(FetchDescriptor<AppSettings>())
        let migratedSettings = try XCTUnwrap(settings.first)
        XCTAssertEqual(migratedSettings.floatingWidgetVisibleCount, 6)
        XCTAssertEqual(migratedSettings.defaultReminderHour, 8)
        XCTAssertEqual(migratedSettings.defaultReminderMinute, 45)
    }

    func testPreviouslyUnversionedCurrentStoreOpensWithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacCalendarCurrentSchema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("unversioned-current.store")
        let copyURL = directory.appendingPathComponent("versioned-current-copy.store")
        let schema = Schema([CalendarEvent.self, HolidayRecord.self, AppSettings.self])
        let configuration = ModelConfiguration(schema: schema, url: originalURL)
        let oldContainer = try ModelContainer(for: schema, configurations: [configuration])
        let eventID = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!
        oldContainer.mainContext.insert(
            CalendarEvent(
                id: eventID,
                title: "Current event",
                startDate: Date(timeIntervalSince1970: 1_900_000_000),
                endDate: Date(timeIntervalSince1970: 1_900_000_000),
                category: .work,
                notes: "Current notes",
                recurrence: .weekly,
                notificationOffsetsDays: [2, 0]
            )
        )
        try oldContainer.mainContext.save()
        try copyStoreFamily(from: originalURL, to: copyURL)

        let migrated = try CalendarStore.makeContainer(at: copyURL)
        let events = try migrated.mainContext.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].id, eventID)
        XCTAssertEqual(events[0].category, .work)
        XCTAssertEqual(events[0].recurrence, .weekly)
        XCTAssertEqual(events[0].notificationOffsetsDays, [2, 0])
    }

    func testLegacyCommitFixtureCopyMigratesAndLeavesOriginalUntouched() throws {
        let sourceURL: URL
        if let sourcePath = ProcessInfo.processInfo.environment["MYMACCALENDAR_LEGACY_FIXTURE_URL"] {
            sourceURL = URL(fileURLWithPath: sourcePath)
        } else {
            sourceURL = try bundledLegacyFixtureURL
        }
        let originalData = try Data(contentsOf: sourceURL)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacCalendarExternalMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copyURL = directory.appendingPathComponent("migration-copy.store")
        let legacyCheckURL = directory.appendingPathComponent("legacy-check.store")
        try copyStoreFamily(from: sourceURL, to: copyURL)
        try copyStoreFamily(from: sourceURL, to: legacyCheckURL)

        try assertMigratedStore(at: copyURL, matchesLegacyStoreAt: legacyCheckURL)
        try assertMigratedStore(at: copyURL, matchesLegacyStoreAt: legacyCheckURL)

        let original = try makeLegacyContainer(at: legacyCheckURL)
        let events = try original.mainContext.fetch(FetchDescriptor<CalendarSchemaV1.CalendarEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].notificationOffsetsDays, [7, 2, 1, 0])
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)
    }

    func testLegacyStoreCopyMigratesAllFieldsAndReopensIdempotently() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacCalendarMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let originalURL = directory.appendingPathComponent("legacy.store")
        let copyURL = directory.appendingPathComponent("migration-copy.store")
        let eventID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_100_000)
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let endDate = Date(timeIntervalSince1970: 1_800_086_400)

        try createLegacyStore(
            at: originalURL,
            eventID: eventID,
            title: "Legacy event",
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        try copyStoreFamily(from: originalURL, to: copyURL)

        try assertMigratedStore(at: copyURL, matchesLegacyStoreAt: originalURL)
        try assertMigratedStore(at: copyURL, matchesLegacyStoreAt: originalURL)

        let original = try makeLegacyContainer(at: originalURL)
        let originalEvents = try original.mainContext.fetch(FetchDescriptor<CalendarSchemaV1.CalendarEvent>())
        XCTAssertEqual(originalEvents.count, 1)
        XCTAssertEqual(originalEvents[0].notificationOffsetsDays, [7, 2, 1, 0])
    }

    private func createLegacyStore(
        at url: URL,
        eventID: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        let container = try makeLegacyContainer(at: url)
        let event = CalendarSchemaV1.CalendarEvent(
            id: eventID,
            title: title,
            startDate: startDate,
            endDate: endDate,
            colorHex: "#123456",
            notes: "Legacy notes",
            recurrenceRaw: "monthly",
            notificationOffsetsDays: [7, 2, 1, 0],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        container.mainContext.insert(event)
        container.mainContext.insert(
            CalendarSchemaV1.HolidayRecord(
                date: startDate,
                title: "Legacy holiday",
                sourceRaw: HolidaySource.manual.rawValue,
                year: 2027
            )
        )
        container.mainContext.insert(
            CalendarSchemaV1.AppSettings(
                floatingWidgetVisibleCount: 8,
                defaultReminderHour: 10,
                defaultReminderMinute: 30
            )
        )
        try container.mainContext.save()
    }

    private func makeLegacyContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CalendarSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeCategorizedLegacyContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CategorizedArrayLegacySchema.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func assertMigratedStore(at url: URL, matchesLegacyStoreAt legacyURL: URL) throws {
        let legacyContainer = try makeLegacyContainer(at: legacyURL)
        let legacyEvent = try XCTUnwrap(
            legacyContainer.mainContext.fetch(FetchDescriptor<CalendarSchemaV1.CalendarEvent>()).first
        )
        let legacyHoliday = try XCTUnwrap(
            legacyContainer.mainContext.fetch(FetchDescriptor<CalendarSchemaV1.HolidayRecord>()).first
        )
        let legacySettings = try XCTUnwrap(
            legacyContainer.mainContext.fetch(FetchDescriptor<CalendarSchemaV1.AppSettings>()).first
        )

        let container = try CalendarStore.makeContainer(at: url)
        let events = try container.mainContext.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.id, legacyEvent.id)
        XCTAssertEqual(event.title, legacyEvent.title)
        XCTAssertEqual(event.startDate, legacyEvent.startDate)
        XCTAssertEqual(event.endDate, legacyEvent.endDate)
        XCTAssertEqual(event.colorHex, legacyEvent.colorHex)
        XCTAssertEqual(event.category, .personal)
        XCTAssertEqual(event.notes, legacyEvent.notes)
        XCTAssertEqual(event.recurrenceRaw, legacyEvent.recurrenceRaw)
        XCTAssertEqual(event.notificationOffsetsDays, legacyEvent.notificationOffsetsDays)
        XCTAssertEqual(event.createdAt, legacyEvent.createdAt)
        XCTAssertEqual(event.updatedAt, legacyEvent.updatedAt)

        let holidays = try container.mainContext.fetch(FetchDescriptor<HolidayRecord>())
        XCTAssertEqual(holidays.count, 1)
        let holiday = try XCTUnwrap(holidays.first)
        XCTAssertEqual(holiday.id, legacyHoliday.id)
        XCTAssertEqual(holiday.date, legacyHoliday.date)
        XCTAssertEqual(holiday.title, legacyHoliday.title)
        XCTAssertEqual(holiday.sourceRaw, legacyHoliday.sourceRaw)
        XCTAssertEqual(holiday.providerKey, legacyHoliday.providerKey)
        XCTAssertEqual(holiday.isHidden, legacyHoliday.isHidden)
        XCTAssertEqual(holiday.year, legacyHoliday.year)
        XCTAssertEqual(holiday.updatedAt, legacyHoliday.updatedAt)

        let settings = try container.mainContext.fetch(FetchDescriptor<AppSettings>())
        XCTAssertEqual(settings.count, 1)
        let migratedSettings = try XCTUnwrap(settings.first)
        XCTAssertEqual(migratedSettings.id, legacySettings.id)
        XCTAssertEqual(migratedSettings.launchAtLogin, legacySettings.launchAtLogin)
        XCTAssertEqual(migratedSettings.showMenuBar, legacySettings.showMenuBar)
        XCTAssertEqual(migratedSettings.floatingWidgetEnabled, legacySettings.floatingWidgetEnabled)
        XCTAssertEqual(migratedSettings.floatingWidgetAlwaysOnTop, legacySettings.floatingWidgetAlwaysOnTop)
        XCTAssertEqual(migratedSettings.floatingWidgetOpacity, legacySettings.floatingWidgetOpacity)
        XCTAssertEqual(migratedSettings.floatingWidgetVisibleCount, legacySettings.floatingWidgetVisibleCount)
        XCTAssertEqual(migratedSettings.defaultReminderHour, legacySettings.defaultReminderHour)
        XCTAssertEqual(migratedSettings.defaultReminderMinute, legacySettings.defaultReminderMinute)
        XCTAssertEqual(migratedSettings.theme, legacySettings.theme)
        XCTAssertEqual(migratedSettings.calendarDensity, legacySettings.calendarDensity)
    }

    private func copyStoreFamily(from source: URL, to destination: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            let sourceFile = URL(fileURLWithPath: source.path + suffix)
            guard FileManager.default.fileExists(atPath: sourceFile.path) else { continue }
            let destinationFile = URL(fileURLWithPath: destination.path + suffix)
            try FileManager.default.copyItem(at: sourceFile, to: destinationFile)
        }
    }

    private var bundledLegacyFixtureURL: URL {
        get throws {
            try XCTUnwrap(
                Bundle.module.url(
                    forResource: "legacy-v1-613d946",
                    withExtension: "store"
                )
            )
        }
    }
}

private enum CategorizedArrayLegacySchema: VersionedSchema {
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
        var categoryRaw: String
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
            colorHex: String = EventCategory.personal.colorHex,
            categoryRaw: String = EventCategory.personal.rawValue,
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
            self.categoryRaw = categoryRaw
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
