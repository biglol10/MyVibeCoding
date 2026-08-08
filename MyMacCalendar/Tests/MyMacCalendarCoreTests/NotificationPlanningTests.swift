import XCTest
@testable import MyMacCalendarCore

final class NotificationPlanningTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testWeeklyRecurrenceProducesPlansForEachOccurrence() throws {
        let event = snapshot(
            id: "10000000-0000-0000-0000-000000000001",
            title: "Weekly",
            start: try date(2026, 7, 1),
            recurrence: .weekly,
            offsets: [1]
        )

        let plans = planner.plans(
            for: [event],
            defaultHour: 9,
            defaultMinute: 0,
            now: try date(2026, 6, 29, hour: 8),
            horizonDays: 20,
            maximumPlans: 20,
            batchID: "weekly"
        )

        XCTAssertEqual(plans.count, 3)
        XCTAssertEqual(plans.map { calendar.component(.day, from: $0.occurrenceDate) }, [1, 8, 15])
    }

    func testMonthEndAndLeapDayPlansUseClampedOccurrences() throws {
        let monthly = snapshot(
            id: "20000000-0000-0000-0000-000000000001",
            title: "Month end",
            start: try date(2026, 1, 31),
            recurrence: .monthly,
            offsets: [0]
        )
        let leap = snapshot(
            id: "20000000-0000-0000-0000-000000000002",
            title: "Leap",
            start: try date(2024, 2, 29),
            recurrence: .yearly,
            offsets: [0]
        )

        let monthlyPlans = planner.plans(
            for: [monthly], defaultHour: 9, defaultMinute: 0,
            now: try date(2026, 2, 1), horizonDays: 60, maximumPlans: 10, batchID: "month"
        )
        let leapPlans = planner.plans(
            for: [leap], defaultHour: 9, defaultMinute: 0,
            now: try date(2025, 1, 1), horizonDays: 60, maximumPlans: 10, batchID: "leap"
        )

        XCTAssertEqual(monthlyPlans.map { calendar.component(.day, from: $0.occurrenceDate) }, [28, 31])
        XCTAssertEqual(leapPlans.map { calendar.component(.day, from: $0.occurrenceDate) }, [28])
    }

    func testHorizonUsesFireDateAndIncludesExactBoundary() throws {
        let event = snapshot(
            id: "30000000-0000-0000-0000-000000000001",
            title: "Boundary",
            start: try date(2026, 8, 31),
            recurrence: .none,
            offsets: [1, 0]
        )
        let now = try date(2026, 6, 1, hour: 9)

        let plans = planner.plans(
            for: [event], defaultHour: 9, defaultMinute: 0,
            now: now, horizonDays: 90, maximumPlans: 10, batchID: "boundary"
        )

        XCTAssertEqual(plans.map(\.offsetDays), [1])
        XCTAssertEqual(plans.first?.fireDate, try date(2026, 8, 30, hour: 9))
    }

    func testDuplicateOffsetsAreRemovedAndNegativeOffsetsRejected() throws {
        let event = snapshot(
            id: "40000000-0000-0000-0000-000000000001",
            title: "Offsets",
            start: try date(2026, 7, 10),
            recurrence: .none,
            offsets: [7, 1, 1, 0, -2]
        )

        let plans = planner.plans(
            for: [event], defaultHour: 9, defaultMinute: 0,
            now: try date(2026, 7, 1), horizonDays: 90, maximumPlans: 10, batchID: "offsets"
        )

        XCTAssertEqual(plans.map(\.offsetDays), [7, 1, 0])
        XCTAssertEqual(Set(plans.map(\.identifier)).count, plans.count)
        XCTAssertTrue(plans.allSatisfy { $0.identifier.contains("occurrence-") && $0.identifier.contains("batch-offsets") })
    }

    func testGlobalMaximumAppliesAfterSortingAcrossEvents() throws {
        let later = snapshot(
            id: "50000000-0000-0000-0000-000000000001",
            title: "Later",
            start: try date(2026, 7, 20),
            recurrence: .none,
            offsets: [0]
        )
        let earlier = snapshot(
            id: "50000000-0000-0000-0000-000000000002",
            title: "Earlier",
            start: try date(2026, 7, 10),
            recurrence: .weekly,
            offsets: [0]
        )

        let plans = planner.plans(
            for: [later, earlier], defaultHour: 9, defaultMinute: 0,
            now: try date(2026, 7, 1), horizonDays: 40, maximumPlans: 2, batchID: "global"
        )

        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans.map(\.eventID), [earlier.id, earlier.id])
        XCTAssertEqual(plans.map { calendar.component(.day, from: $0.fireDate) }, [10, 17])
    }

    func testExtremePositiveOffsetIsIgnoredWithoutOverflowing() throws {
        let event = snapshot(
            id: "60000000-0000-0000-0000-000000000001",
            title: "Corrupted offset",
            start: try date(2026, 7, 10),
            recurrence: .none,
            offsets: [Int.max]
        )

        let plans = planner.plans(
            for: [event], defaultHour: 9, defaultMinute: 0,
            now: try date(2026, 7, 1), horizonDays: 90, maximumPlans: 10, batchID: "overflow"
        )

        XCTAssertTrue(plans.isEmpty)
    }

    private var planner: NotificationPlanner {
        NotificationPlanner(calendar: calendar)
    }

    private func snapshot(
        id: String,
        title: String,
        start: Date,
        recurrence: EventRecurrence,
        offsets: [Int]
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: UUID(uuidString: id)!,
            title: title,
            startDate: start,
            endDate: start,
            colorHex: "#4F7DFF",
            recurrence: recurrence,
            notificationOffsetsDays: offsets
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }
}
