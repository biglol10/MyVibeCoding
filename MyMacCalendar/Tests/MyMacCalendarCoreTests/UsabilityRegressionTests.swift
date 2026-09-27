import Foundation
import SwiftData
import XCTest
@testable import MyMacCalendarCore

@MainActor
final class UsabilityRegressionTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testAllDayDatesAndMonthlyRecurrenceStayOnSameCivilDayAfterTravel() throws {
        let seoul = calendar("Asia/Seoul")
        let losAngeles = calendar("America/Los_Angeles")
        let event = CalendarEvent(title: "월말", startDate: date(2026, 1, 31, in: seoul),
                                  endDate: date(2026, 2, 2, in: seoul), recurrence: .monthly,
                                  notificationOffsetsDays: [0], calendar: seoul)
        XCTAssertEqual(event.localStartDate(in: losAngeles), date(2026, 1, 31, in: losAngeles))
        let occurrences = RecurrenceExpander(calendar: losAngeles).occurrences(for: event, in:
            DateInterval(start: date(2026, 2, 1, in: losAngeles), end: date(2026, 4, 1, in: losAngeles)))
        XCTAssertEqual(occurrences.map(\.startDate), [date(2026, 1, 31, in: losAngeles), date(2026, 2, 28, in: losAngeles), date(2026, 3, 31, in: losAngeles)])
        let plans = NotificationPlanner(calendar: losAngeles).plans(for: [CalendarEventSnapshot(event: event)], defaultHour: 9,
            defaultMinute: 0, now: date(2026, 3, 1, in: losAngeles), horizonDays: 31, batchID: "travel")
        XCTAssertEqual(plans.first?.fireDate, date(2026, 3, 31, in: losAngeles, hour: 9))
    }

    func testEditingAfterTravelKeepsRangeWhenReturningHome() {
        let seoul = calendar("Asia/Seoul")
        let losAngeles = calendar("America/Los_Angeles")
        let event = CalendarEvent(title: "여행", startDate: date(2026, 9, 28, in: seoul),
                                  endDate: date(2026, 9, 30, in: seoul), calendar: seoul)
        event.setDateRange(start: event.localStartDate(in: losAngeles), end: date(2026, 10, 1, in: losAngeles), calendar: losAngeles)
        XCTAssertEqual(event.localStartDate(in: seoul), date(2026, 9, 28, in: seoul))
        XCTAssertEqual(event.localEndDate(in: seoul), date(2026, 10, 1, in: seoul))
    }

    func testV3MigrationPreservesRawDatesAndPinsCivilDatesAcrossReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("v3.store")
        let originalDate = Calendar.current.startOfDay(for: Date())
        let eventID = UUID()
        do {
            let schema = Schema(versionedSchema: CalendarSchemaV3.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            old.mainContext.insert(CalendarSchemaV3.CalendarEvent(id: eventID, title: "보존",
                startDate: originalDate, endDate: originalDate, category: .work, notes: "메모", recurrence: .yearly, notificationOffsetsDays: [7, 0]))
            old.mainContext.insert(CalendarSchemaV3.HolidayRecord(date: originalDate, title: "숨긴 휴일", source: .api, isHidden: true, year: 2026))
            old.mainContext.insert(CalendarSchemaV3.AppSettings(floatingWidgetVisibleCount: 8))
            try old.mainContext.save()
        }
        for _ in 0..<2 {
            let migrated = try CalendarStore.makeContainer(at: url)
            let event = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<CalendarEvent>()).first)
            XCTAssertEqual(event.id, eventID)
            XCTAssertEqual(event.startDate, originalDate)
            XCTAssertEqual(event.notes, "메모")
            XCTAssertEqual(event.recurrence, .yearly)
            XCTAssertEqual(event.notificationOffsetsDays, [7, 0])
            XCTAssertEqual(event.category, .work)
            XCTAssertEqual(event.dateTimeZoneIdentifier, TimeZone.current.identifier)
            let target = calendar("America/Los_Angeles")
            var source = calendar(TimeZone.current.identifier)
            source.locale = Locale(identifier: "en_US_POSIX")
            XCTAssertEqual(target.dateComponents([.year, .month, .day], from: event.localStartDate(in: target)),
                           source.dateComponents([.year, .month, .day], from: originalDate))
            let holiday = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<HolidayRecord>()).first)
            XCTAssertTrue(holiday.isHidden)
            XCTAssertEqual(holiday.date, originalDate)
            XCTAssertEqual(holiday.dateTimeZoneIdentifier, TimeZone.current.identifier)
            XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<AppSettings>()).first?.floatingWidgetVisibleCount, 8)
        }
    }

    func testMonthNavigationKeepsSelectionInsideDisplayedMonthIncludingLeapDay() {
        let cal = calendar("Asia/Seoul")
        XCTAssertEqual(CalendarNavigation.movingMonth(from: date(2026, 1, 31, in: cal), selectedDate: date(2026, 1, 31, in: cal), by: 1, calendar: cal), date(2026, 2, 28, in: cal))
        XCTAssertEqual(CalendarNavigation.movingMonth(from: date(2028, 1, 31, in: cal), selectedDate: date(2028, 1, 31, in: cal), by: 1, calendar: cal), date(2028, 2, 29, in: cal))
        XCTAssertEqual(CalendarNavigation.movingMonth(from: date(2026, 12, 27, in: cal), selectedDate: date(2026, 12, 27, in: cal), by: 1, calendar: cal), date(2027, 1, 27, in: cal))
    }

    func testFullUpcomingListIncludesEveryEventAndOneHundredDayFutureEvent() {
        let cal = calendar("Asia/Seoul")
        let today = date(2026, 9, 27, in: cal)
        var events = (1...15).map { CalendarEvent(title: "일정 \($0)", startDate: today, endDate: today, calendar: cal) }
        let later = cal.date(byAdding: .day, value: 100, to: today)!
        events.append(CalendarEvent(title: "100일 뒤", startDate: later, endDate: later, calendar: cal))
        XCTAssertEqual(EventService(calendar: cal).upcomingYearOccurrences(from: today, events: events).count, 16)
    }

    func testHiddenHolidayRestoresWithoutDuplicateOnReimport() throws {
        let container = try CalendarStore.makeInMemoryContainer()
        let context = container.mainContext
        let date = Calendar.current.startOfDay(for: Date())
        let year = Calendar.current.component(.year, from: date)
        let holiday = HolidayRecord(date: date, title: "휴일", source: .api, providerKey: "test-holiday", isHidden: true, year: year)
        context.insert(holiday)
        try context.save()
        holiday.isHidden = false
        try PersistenceTransaction.save(context: context)
        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<HolidayRecord>()).first)
        XCTAssertFalse(restored.isHidden)
        let imports = [HolidayImport(date: date, title: "휴일", providerKey: "test-holiday")]
        XCTAssertTrue(HolidayImportPlanner().newRecords(imports: imports, existing: [restored], year: year).isEmpty)
    }

    func testFortySimultaneousRemindersAreAllIncludedAndRefreshRemovesDeletedMember() async throws {
        let cal = calendar("Asia/Seoul")
        let client = FakeNotificationClient()
        let coordinator = NotificationUpdateCoordinator(client: client, planner: NotificationPlanner(calendar: cal))
        let events = (1...40).map { snapshot(title: "일정 \($0)", date: date(2026, 9, 28, in: cal)) }
        await coordinator.refresh(events: events, defaultHour: 9, defaultMinute: 0, now: date(2026, 9, 27, in: cal))
        XCTAssertEqual(client.pending.count, 1)
        XCTAssertEqual(coordinator.status, .scheduled(reminders: 40, requests: 1, deferred: 0))
        let schedule = NotificationSchedule(plans: NotificationPlanner(calendar: cal).plans(for: events, defaultHour: 9,
            defaultMinute: 0, now: date(2026, 9, 27, in: cal), maximumPlans: Int.max, batchID: "test"), maximumRequests: 32, batchID: "test")
        for event in events { XCTAssertTrue(schedule.requests[0].body.contains("\(event.title) (당일)")) }
        await coordinator.refresh(events: Array(events.dropFirst()), defaultHour: 9, defaultMinute: 0, now: date(2026, 9, 27, in: cal))
        XCTAssertEqual(client.pending.count, 1)
        XCTAssertEqual(coordinator.status, .scheduled(reminders: 39, requests: 1, deferred: 0))
    }

    func testPendingLimitAndPermissionFailuresProduceVisibleStatuses() async {
        let cal = calendar("Asia/Seoul")
        let client = FakeNotificationClient()
        let coordinator = NotificationUpdateCoordinator(client: client, planner: NotificationPlanner(calendar: cal))
        let now = date(2026, 9, 1, in: cal)
        let events = (1...40).map { snapshot(title: "일정 \($0)", date: cal.date(byAdding: .day, value: $0, to: now)!) }
        await coordinator.refresh(events: events, defaultHour: 9, defaultMinute: 0, now: now)
        XCTAssertEqual(coordinator.status, .scheduled(reminders: 32, requests: 32, deferred: 8))
        XCTAssertTrue(coordinator.status.needsAttention)
        client.authorizationResult = .denied
        await coordinator.refresh(events: events, defaultHour: 9, defaultMinute: 0, now: now)
        XCTAssertEqual(coordinator.status, .denied)
        client.authorizationResult = .authorized
        client.addFailureCalls = [client.addCallCount + 1]
        await coordinator.refresh(events: events, defaultHour: 9, defaultMinute: 0, now: now)
        XCTAssertEqual(coordinator.status, .failed)
        client.addFailureCalls = []
        await coordinator.refresh(events: events, defaultHour: 9, defaultMinute: 0, now: now)
        XCTAssertEqual(coordinator.status, .scheduled(reminders: 32, requests: 32, deferred: 8))
    }

    func testDeletingNonOwnerOfGroupedReminderCancelsInFlightGroup() async throws {
        let cal = calendar("Asia/Seoul")
        let client = FakeNotificationClient()
        client.blockedAddCalls = [1]
        let coordinator = NotificationUpdateCoordinator(client: client, planner: NotificationPlanner(calendar: cal))
        let first = CalendarEventSnapshot(id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!, title: "그룹 소유자",
            startDate: date(2026, 9, 28, in: cal), endDate: date(2026, 9, 28, in: cal), colorHex: "", recurrence: .none, notificationOffsetsDays: [0])
        let second = CalendarEventSnapshot(id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!, title: "삭제할 일정",
            startDate: date(2026, 9, 28, in: cal), endDate: date(2026, 9, 28, in: cal), colorHex: "", recurrence: .none, notificationOffsetsDays: [0])
        let refresh = Task {
            await coordinator.refresh(events: [first, second], defaultHour: 9, defaultMinute: 0, now: date(2026, 9, 27, in: cal))
        }
        await client.waitForAddCalls(1)
        let deletion = Task { try await coordinator.delete(eventID: second.id) }
        // Give deletion a deterministic main-actor turn before the late add completes.
        await Task.yield()
        client.resumeAdd(call: 1)
        _ = try await deletion.value
        await refresh.value
        XCTAssertTrue(client.pending.isEmpty)
        await coordinator.refresh(events: [first], defaultHour: 9, defaultMinute: 0, now: date(2026, 9, 27, in: cal))
        XCTAssertEqual(client.pending.count, 1)
        XCTAssertEqual(coordinator.status, .scheduled(reminders: 1, requests: 1, deferred: 0))
    }

    private func snapshot(title: String, date: Date) -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: UUID(), title: title, startDate: date, endDate: date, colorHex: "#FFFFFF", recurrence: .none, notificationOffsetsDays: [0])
    }
}
