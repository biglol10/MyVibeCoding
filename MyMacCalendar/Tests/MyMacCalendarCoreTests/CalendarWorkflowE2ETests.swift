import SwiftData
import XCTest
@testable import MyMacCalendarCore

final class CalendarWorkflowE2ETests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testCreateEditAndDeleteEventWorkflow() throws {
        let container = try CalendarStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let start = try date(2026, 6, 30)
        let event = CalendarEvent(
            title: "codex 만료",
            startDate: start,
            endDate: start,
            notes: "renew subscription",
            recurrence: .none,
            notificationOffsetsDays: [7, 2, 1, 0]
        )

        context.insert(event)
        try context.save()

        let saved = try context.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].title, "codex 만료")
        XCTAssertEqual(saved[0].notificationOffsetsDays, [7, 2, 1, 0])

        saved[0].title = "codex 갱신"
        saved[0].notificationOffsetsDays = [2, 1]
        saved[0].updatedAt = try date(2026, 6, 25)
        try context.save()

        let updated = try XCTUnwrap(context.fetch(FetchDescriptor<CalendarEvent>()).first)
        XCTAssertEqual(updated.title, "codex 갱신")
        XCTAssertEqual(updated.notificationOffsetsDays, [2, 1])

        context.delete(updated)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertTrue(remaining.isEmpty)
    }

    func testManualHolidayAndHiddenImportedHolidayWorkflow() throws {
        let container = try CalendarStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let holidayDate = try date(2026, 6, 3)
        let imported = HolidayRecord(
            date: holidayDate,
            title: "Wrong Imported Holiday",
            source: .api,
            providerKey: "2026-06-03-Wrong Imported Holiday",
            year: 2026
        )

        context.insert(imported)
        try context.save()

        imported.isHidden = true
        let manual = HolidayRecord(date: holidayDate, title: "지방 선거일", source: .manual, year: 2026)
        context.insert(manual)
        try context.save()

        let imports = [
            HolidayImport(
                date: holidayDate,
                title: "Wrong Imported Holiday",
                providerKey: "2026-06-03-Wrong Imported Holiday"
            )
        ]
        let existing = try context.fetch(FetchDescriptor<HolidayRecord>())
        let visible = HolidayMerger().merge(imports: imports, existing: existing, year: 2026)

        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible[0].title, "지방 선거일")
        XCTAssertEqual(visible[0].source, .manual)
        XCTAssertTrue(try XCTUnwrap(existing.first { $0.source == .api }).isHidden)
    }

    func testSettingsAndUpcomingWidgetWorkflow() throws {
        let container = try CalendarStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let settingsStore = SettingsStore(context: context)

        let settings = try settingsStore.load()
        settings.floatingWidgetEnabled = false
        settings.floatingWidgetAlwaysOnTop = false
        settings.floatingWidgetVisibleCount = 2
        settings.defaultReminderHour = 8
        settings.defaultReminderMinute = 30

        let today = try date(2026, 6, 25)
        let tomorrow = try date(2026, 6, 26)
        let later = try date(2026, 6, 30)
        context.insert(CalendarEvent(title: "오늘 마감", startDate: today, endDate: today))
        context.insert(CalendarEvent(title: "내일 회의", startDate: tomorrow, endDate: tomorrow))
        context.insert(CalendarEvent(title: "다음 주 준비", startDate: later, endDate: later))
        try context.save()

        let loadedSettings = try settingsStore.load()
        XCTAssertFalse(loadedSettings.floatingWidgetEnabled)
        XCTAssertFalse(loadedSettings.floatingWidgetAlwaysOnTop)
        XCTAssertEqual(loadedSettings.floatingWidgetVisibleCount, 2)
        XCTAssertEqual(loadedSettings.defaultReminderHour, 8)
        XCTAssertEqual(loadedSettings.defaultReminderMinute, 30)

        let events = try context.fetch(FetchDescriptor<CalendarEvent>())
        let upcoming = EventService(calendar: calendar).upcomingEvents(
            from: today,
            events: events,
            limit: loadedSettings.floatingWidgetVisibleCount
        )

        XCTAssertEqual(upcoming.map(\.title), ["오늘 마감", "내일 회의"])
    }

    func testMultipleDatesWithMultipleEventsWorkflow() throws {
        let container = try CalendarStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let service = EventService(calendar: calendar)

        let june24 = try date(2026, 6, 24)
        let june25 = try date(2026, 6, 25)
        let june26 = try date(2026, 6, 26)
        let june30 = try date(2026, 6, 30)

        let events = [
            CalendarEvent(title: "병원 예약", startDate: june24, endDate: june24, notes: "오전"),
            CalendarEvent(title: "보고서 제출", startDate: june24, endDate: june24),
            CalendarEvent(title: "팀 점심", startDate: june24, endDate: june24),
            CalendarEvent(title: "월급 확인", startDate: june25, endDate: june25),
            CalendarEvent(title: "운동", startDate: june25, endDate: june25),
            CalendarEvent(title: "가족 모임", startDate: june26, endDate: june26),
            CalendarEvent(title: "세금 납부", startDate: june26, endDate: june26, notificationOffsetsDays: [7, 2, 1]),
            CalendarEvent(title: "장보기", startDate: june26, endDate: june26),
            CalendarEvent(title: "영화 예매", startDate: june26, endDate: june26),
            CalendarEvent(title: "구독 갱신", startDate: june30, endDate: june30)
        ]

        events.forEach(context.insert)
        try context.save()

        let saved = try context.fetch(FetchDescriptor<CalendarEvent>(sortBy: [SortDescriptor(\.startDate), SortDescriptor(\.title)]))
        XCTAssertEqual(saved.count, 10)
        XCTAssertEqual(titles(on: june24, in: saved), ["병원 예약", "보고서 제출", "팀 점심"])
        XCTAssertEqual(titles(on: june25, in: saved), ["운동", "월급 확인"])
        XCTAssertEqual(titles(on: june26, in: saved), ["가족 모임", "세금 납부", "영화 예매", "장보기"])
        XCTAssertEqual(titles(on: june30, in: saved), ["구독 갱신"])

        let upcoming = service.upcomingEvents(from: june24, events: saved, limit: 5)
        XCTAssertEqual(upcoming.map(\.title), ["병원 예약", "보고서 제출", "팀 점심", "운동", "월급 확인"])

        let taxEvent = try XCTUnwrap(saved.first { $0.title == "세금 납부" })
        XCTAssertEqual(taxEvent.notificationOffsetsDays, [7, 2, 1])
        XCTAssertEqual(service.deletePlan(for: taxEvent).notificationIdentifiers.count, 3)

        let searchResults = service.search("예", in: saved)
        XCTAssertEqual(searchResults.map(\.title), ["병원 예약", "영화 예매"])

        context.delete(taxEvent)
        try context.save()

        let afterDelete = try context.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertEqual(afterDelete.count, 9)
        XCTAssertEqual(titles(on: june26, in: afterDelete), ["가족 모임", "영화 예매", "장보기"])
        XCTAssertFalse(afterDelete.contains { $0.title == "세금 납부" })
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private func titles(on date: Date, in events: [CalendarEvent]) -> [String] {
        events
            .filter { calendar.isDate($0.startDate, inSameDayAs: date) }
            .map(\.title)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
