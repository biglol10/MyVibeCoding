# MyMacCalendar Implementation Plan

Status: Historical implementation plan. This file is kept for traceability and contains planned file names and snippets that may no longer match the current app. Use `README.md`, current source files, and tests as the source of truth.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-first SwiftUI macOS calendar app with all-day events, simple recurrence, editable holidays, notifications, quick add, menu bar access, settings, and an always-on-top floating upcoming-events widget.

**Architecture:** Use a Swift Package with a testable `MyMacCalendarCore` library and a `MyMacCalendar` macOS executable target. Keep date logic, parsing, holiday merging, notification planning, and persistence boundaries separate so most behavior is unit-testable before UI work starts.

**Tech Stack:** Swift 6.1.2, macOS 14+, SwiftUI, SwiftData, AppKit, UserNotifications, XCTest, SwiftPM, Nager.Date public holiday API (`https://date.nager.at/api/v3/PublicHolidays/{year}/KR`).

---

Repository root: `/Users/biglol/Desktop/practice/MyMacCalendar`

Design spec: `docs/superpowers/specs/2026-06-25-mymaccalendar-design.md`

## File Structure

- `Package.swift`: SwiftPM package with app, core library, and test target.
- `Sources/MyMacCalendar/App/MyMacCalendarApp.swift`: SwiftUI app entry point and scene wiring.
- `Sources/MyMacCalendar/App/AppDelegate.swift`: AppKit hooks for menu bar and floating widget lifecycle.
- `Sources/MyMacCalendar/Views/MainWindowView.swift`: Main window shell.
- `Sources/MyMacCalendar/Views/MonthGridView.swift`: Month calendar grid.
- `Sources/MyMacCalendar/Views/AgendaPanelView.swift`: Selected-day and upcoming agenda panel.
- `Sources/MyMacCalendar/Views/EventEditorView.swift`: Create, edit, and delete all-day events.
- `Sources/MyMacCalendar/Views/QuickAddView.swift`: Quick-add confirmation UI.
- `Sources/MyMacCalendar/Views/SettingsView.swift`: Settings tabs.
- `Sources/MyMacCalendar/Views/FloatingWidgetView.swift`: Floating upcoming-events UI.
- `Sources/MyMacCalendar/Controllers/MenuBarController.swift`: `NSStatusItem` menu bar integration.
- `Sources/MyMacCalendar/Controllers/FloatingWidgetController.swift`: Always-on-top widget window.
- `Sources/MyMacCalendarCore/Models/CalendarEvent.swift`: SwiftData event model and recurrence enum.
- `Sources/MyMacCalendarCore/Models/HolidayRecord.swift`: SwiftData holiday model and source enum.
- `Sources/MyMacCalendarCore/Models/AppSettings.swift`: SwiftData settings model.
- `Sources/MyMacCalendarCore/Services/CalendarGridBuilder.swift`: Month grid calculation.
- `Sources/MyMacCalendarCore/Services/EventService.swift`: Event CRUD helper logic, search, upcoming, deletion planning.
- `Sources/MyMacCalendarCore/Services/RecurrenceExpander.swift`: Weekly, monthly, yearly recurrence expansion.
- `Sources/MyMacCalendarCore/Services/HolidayService.swift`: Holiday fetch, decode, merge, manual edits, hidden API rows.
- `Sources/MyMacCalendarCore/Services/NotificationService.swift`: Notification request planning and UserNotifications bridge.
- `Sources/MyMacCalendarCore/Services/QuickAddParser.swift`: Fast natural input parser.
- `Sources/MyMacCalendarCore/Stores/CalendarStore.swift`: SwiftData model container and persistence access.
- `Sources/MyMacCalendarCore/Stores/SettingsStore.swift`: Settings defaults and updates.
- `Tests/MyMacCalendarCoreTests/CalendarGridBuilderTests.swift`
- `Tests/MyMacCalendarCoreTests/RecurrenceExpanderTests.swift`
- `Tests/MyMacCalendarCoreTests/EventServiceTests.swift`
- `Tests/MyMacCalendarCoreTests/HolidayServiceTests.swift`
- `Tests/MyMacCalendarCoreTests/NotificationServiceTests.swift`
- `Tests/MyMacCalendarCoreTests/QuickAddParserTests.swift`
- `Tests/MyMacCalendarCoreTests/SettingsStoreTests.swift`
- `scripts/build_app.sh`: Build a `.app` bundle from the SwiftPM executable.

## Task 1: SwiftPM Scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/MyMacCalendarCore/Version.swift`
- Create: `Sources/MyMacCalendar/App/MyMacCalendarApp.swift`
- Create: `Sources/MyMacCalendar/Views/MainWindowView.swift`
- Create: `Tests/MyMacCalendarCoreTests/VersionTests.swift`

- [ ] **Step 1: Write the smoke test**

Create `Tests/MyMacCalendarCoreTests/VersionTests.swift`:

```swift
import XCTest
@testable import MyMacCalendarCore

final class VersionTests: XCTestCase {
    func testVersionName() {
        XCTAssertEqual(AppVersion.name, "MyMacCalendar")
    }
}
```

- [ ] **Step 2: Create package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyMacCalendar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MyMacCalendarCore", targets: ["MyMacCalendarCore"]),
        .executable(name: "MyMacCalendar", targets: ["MyMacCalendar"])
    ],
    targets: [
        .target(
            name: "MyMacCalendarCore",
            path: "Sources/MyMacCalendarCore"
        ),
        .executableTarget(
            name: "MyMacCalendar",
            dependencies: ["MyMacCalendarCore"],
            path: "Sources/MyMacCalendar"
        ),
        .testTarget(
            name: "MyMacCalendarCoreTests",
            dependencies: ["MyMacCalendarCore"],
            path: "Tests/MyMacCalendarCoreTests"
        )
    ]
)
```

- [ ] **Step 3: Add minimal core and app files**

Create `Sources/MyMacCalendarCore/Version.swift`:

```swift
public enum AppVersion {
    public static let name = "MyMacCalendar"
}
```

Create `Sources/MyMacCalendar/App/MyMacCalendarApp.swift`:

```swift
import SwiftUI
import MyMacCalendarCore

@main
struct MyMacCalendarApp: App {
    var body: some Scene {
        WindowGroup(AppVersion.name) {
            MainWindowView()
        }
    }
}
```

Create `Sources/MyMacCalendar/Views/MainWindowView.swift`:

```swift
import SwiftUI

struct MainWindowView: View {
    var body: some View {
        Text("MyMacCalendar")
            .frame(minWidth: 900, minHeight: 620)
    }
}
```

- [ ] **Step 4: Verify tests and app target compile**

Run:

```bash
swift test
swift build
```

Expected: both commands exit `0`, and `VersionTests.testVersionName` passes.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore: scaffold Swift package"
```

## Task 2: Core Models and Month Grid

**Files:**
- Create: `Sources/MyMacCalendarCore/Models/CalendarEvent.swift`
- Create: `Sources/MyMacCalendarCore/Models/HolidayRecord.swift`
- Create: `Sources/MyMacCalendarCore/Services/CalendarGridBuilder.swift`
- Create: `Tests/MyMacCalendarCoreTests/CalendarGridBuilderTests.swift`

- [ ] **Step 1: Write month grid tests**

Create `Tests/MyMacCalendarCoreTests/CalendarGridBuilderTests.swift`:

```swift
import XCTest
@testable import MyMacCalendarCore

final class CalendarGridBuilderTests: XCTestCase {
    func testJune2026StartsOnMondayAndHasThirtyDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let builder = CalendarGridBuilder(calendar: calendar)
        let cells = try builder.makeMonthGrid(year: 2026, month: 6)

        XCTAssertEqual(cells.count, 42)
        XCTAssertEqual(cells[0].day, 31)
        XCTAssertFalse(cells[0].isInDisplayedMonth)
        XCTAssertEqual(cells[1].day, 1)
        XCTAssertTrue(cells[1].isInDisplayedMonth)
        XCTAssertEqual(cells[30].day, 30)
        XCTAssertTrue(cells[30].isInDisplayedMonth)
        XCTAssertEqual(cells[31].day, 1)
        XCTAssertFalse(cells[31].isInDisplayedMonth)
    }

    func testWeekendFlags() throws {
        let builder = CalendarGridBuilder(calendar: Calendar(identifier: .gregorian))
        let cells = try builder.makeMonthGrid(year: 2026, month: 6)

        let sunday = try XCTUnwrap(cells.first { $0.day == 7 && $0.isInDisplayedMonth })
        let saturday = try XCTUnwrap(cells.first { $0.day == 6 && $0.isInDisplayedMonth })

        XCTAssertTrue(sunday.isSunday)
        XCTAssertFalse(sunday.isSaturday)
        XCTAssertTrue(saturday.isSaturday)
        XCTAssertFalse(saturday.isSunday)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter CalendarGridBuilderTests
```

Expected: build fails because `CalendarGridBuilder` is not defined.

- [ ] **Step 3: Add models and grid builder**

Create `Sources/MyMacCalendarCore/Models/CalendarEvent.swift`:

```swift
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
```

Create `Sources/MyMacCalendarCore/Models/HolidayRecord.swift`:

```swift
import Foundation
import SwiftData

public enum HolidaySource: String, Codable, CaseIterable {
    case api
    case manual
}

@Model
public final class HolidayRecord {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var title: String
    public var sourceRaw: String
    public var providerKey: String
    public var isHidden: Bool
    public var year: Int
    public var updatedAt: Date

    public init(
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

    public var source: HolidaySource {
        get { HolidaySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
```

Create `Sources/MyMacCalendarCore/Services/CalendarGridBuilder.swift`:

```swift
import Foundation

public struct CalendarDayCell: Equatable {
    public let date: Date
    public let day: Int
    public let isInDisplayedMonth: Bool
    public let isToday: Bool
    public let isSunday: Bool
    public let isSaturday: Bool
}

public enum CalendarGridError: Error {
    case invalidMonth
}

public struct CalendarGridBuilder {
    private var calendar: Calendar

    public init(calendar: Calendar = .current) {
        var configured = calendar
        configured.firstWeekday = 1
        self.calendar = configured
    }

    public func makeMonthGrid(year: Int, month: Int, today: Date = Date()) throws -> [CalendarDayCell] {
        guard (1...12).contains(month) else { throw CalendarGridError.invalidMonth }
        let monthStart = try makeDate(year: year, month: month, day: 1)
        let dayRange = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<1
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingDays = weekday - calendar.firstWeekday
        let normalizedLeadingDays = leadingDays >= 0 ? leadingDays : leadingDays + 7
        let firstCellDate = calendar.date(byAdding: .day, value: -normalizedLeadingDays, to: monthStart) ?? monthStart

        return (0..<42).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: firstCellDate) ?? firstCellDate
            let components = calendar.dateComponents([.day, .month, .weekday], from: date)
            let day = components.day ?? 1
            let weekday = components.weekday ?? 1
            return CalendarDayCell(
                date: calendar.startOfDay(for: date),
                day: day,
                isInDisplayedMonth: components.month == month && dayRange.contains(day),
                isToday: calendar.isDate(date, inSameDayAs: today),
                isSunday: weekday == 1,
                isSaturday: weekday == 7
            )
        }
    }

    private func makeDate(year: Int, month: Int, day: Int) throws -> Date {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            throw CalendarGridError.invalidMonth
        }
        return calendar.startOfDay(for: date)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter CalendarGridBuilderTests
```

Expected: both grid tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCalendarCore/Models Sources/MyMacCalendarCore/Services/CalendarGridBuilder.swift Tests/MyMacCalendarCoreTests/CalendarGridBuilderTests.swift
git commit -m "feat: add calendar models and month grid"
```

## Task 3: Recurrence and Event Service

**Files:**
- Create: `Sources/MyMacCalendarCore/Services/RecurrenceExpander.swift`
- Create: `Sources/MyMacCalendarCore/Services/EventService.swift`
- Create: `Tests/MyMacCalendarCoreTests/RecurrenceExpanderTests.swift`
- Create: `Tests/MyMacCalendarCoreTests/EventServiceTests.swift`

- [ ] **Step 1: Write recurrence tests**

Create `Tests/MyMacCalendarCoreTests/RecurrenceExpanderTests.swift`:

```swift
import XCTest
@testable import MyMacCalendarCore

final class RecurrenceExpanderTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testWeeklyExpansionWithinRange() throws {
        let start = try date(2026, 6, 1)
        let event = CalendarEvent(title: "Weekly Sync", startDate: start, endDate: start, recurrence: .weekly)
        let range = DateInterval(start: try date(2026, 6, 1), end: try date(2026, 6, 30))

        let occurrences = RecurrenceExpander(calendar: calendar).occurrences(for: event, in: range)

        XCTAssertEqual(occurrences.map { calendar.component(.day, from: $0.startDate) }, [1, 8, 15, 22, 29])
    }

    func testMonthlyExpansionKeepsDayOfMonth() throws {
        let start = try date(2026, 1, 25)
        let event = CalendarEvent(title: "Monthly Bill", startDate: start, endDate: start, recurrence: .monthly)
        let range = DateInterval(start: try date(2026, 1, 1), end: try date(2026, 4, 1))

        let occurrences = RecurrenceExpander(calendar: calendar).occurrences(for: event, in: range)

        XCTAssertEqual(occurrences.map { calendar.component(.month, from: $0.startDate) }, [1, 2, 3])
        XCTAssertEqual(occurrences.map { calendar.component(.day, from: $0.startDate) }, [25, 25, 25])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
```

- [ ] **Step 2: Write event service tests**

Create `Tests/MyMacCalendarCoreTests/EventServiceTests.swift`:

```swift
import XCTest
@testable import MyMacCalendarCore

final class EventServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testUpcomingSortsByDateThenTitle() throws {
        let events = [
            CalendarEvent(title: "B", startDate: try date(2026, 6, 27), endDate: try date(2026, 6, 27)),
            CalendarEvent(title: "A", startDate: try date(2026, 6, 27), endDate: try date(2026, 6, 27)),
            CalendarEvent(title: "Earlier", startDate: try date(2026, 6, 26), endDate: try date(2026, 6, 26))
        ]

        let upcoming = EventService(calendar: calendar).upcomingEvents(from: try date(2026, 6, 25), events: events, limit: 3)

        XCTAssertEqual(upcoming.map(\.title), ["Earlier", "A", "B"])
    }

    func testUpcomingOccurrencesIncludeWeeklyRepeats() throws {
        let weekly = CalendarEvent(title: "Weekly", startDate: try date(2026, 6, 1), endDate: try date(2026, 6, 1), recurrence: .weekly)

        let occurrences = EventService(calendar: calendar).upcomingOccurrences(from: try date(2026, 6, 25), events: [weekly], limit: 2, horizonDays: 21)

        XCTAssertEqual(occurrences.map { calendar.component(.day, from: $0.startDate) }, [29, 6])
    }

    func testSearchMatchesTitleAndNotes() throws {
        let events = [
            CalendarEvent(title: "Doctor", startDate: try date(2026, 6, 26), endDate: try date(2026, 6, 26), notes: "Gangnam"),
            CalendarEvent(title: "Codex Renewal", startDate: try date(2026, 6, 30), endDate: try date(2026, 6, 30))
        ]

        let service = EventService(calendar: calendar)

        XCTAssertEqual(service.search("codex", in: events).map(\.title), ["Codex Renewal"])
        XCTAssertEqual(service.search("gangnam", in: events).map(\.title), ["Doctor"])
    }

    func testDeletePlanContainsEventAndNotificationIdentifiers() throws {
        let event = CalendarEvent(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Delete Me",
            startDate: try date(2026, 6, 30),
            endDate: try date(2026, 6, 30),
            notificationOffsetsDays: [7, 1, 0]
        )

        let plan = EventService(calendar: calendar).deletePlan(for: event)

        XCTAssertEqual(plan.eventID, event.id)
        XCTAssertEqual(plan.notificationIdentifiers.sorted(), [
            "event-11111111-1111-1111-1111-111111111111-offset-0",
            "event-11111111-1111-1111-1111-111111111111-offset-1",
            "event-11111111-1111-1111-1111-111111111111-offset-7"
        ])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
```

- [ ] **Step 3: Run tests to verify failure**

```bash
swift test --filter RecurrenceExpanderTests
swift test --filter EventServiceTests
```

Expected: build fails because `RecurrenceExpander` and `EventService` are not defined.

- [ ] **Step 4: Implement recurrence and event service**

Create `Sources/MyMacCalendarCore/Services/RecurrenceExpander.swift`:

```swift
import Foundation

public struct EventOccurrence: Equatable {
    public let eventID: UUID
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let colorHex: String
}

public struct RecurrenceExpander {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func occurrences(for event: CalendarEvent, in interval: DateInterval) -> [EventOccurrence] {
        let duration = calendar.dateComponents([.day], from: calendar.startOfDay(for: event.startDate), to: calendar.startOfDay(for: event.endDate)).day ?? 0
        var result: [EventOccurrence] = []
        var cursor = calendar.startOfDay(for: event.startDate)

        while cursor < interval.end {
            let occurrenceEnd = calendar.date(byAdding: .day, value: duration, to: cursor) ?? cursor
            if occurrenceEnd >= interval.start && cursor < interval.end {
                result.append(EventOccurrence(eventID: event.id, title: event.title, startDate: cursor, endDate: occurrenceEnd, colorHex: event.colorHex))
            }

            guard event.recurrence != .none else { break }
            guard let next = nextDate(after: cursor, recurrence: event.recurrence) else { break }
            if next <= cursor { break }
            cursor = next
        }

        return result
    }

    private func nextDate(after date: Date, recurrence: EventRecurrence) -> Date? {
        switch recurrence {
        case .none:
            return nil
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}
```

Create `Sources/MyMacCalendarCore/Services/EventService.swift`:

```swift
import Foundation

public struct EventDeletePlan: Equatable {
    public let eventID: UUID
    public let notificationIdentifiers: [String]
}

public struct EventService {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func upcomingEvents(from startDate: Date, events: [CalendarEvent], limit: Int) -> [CalendarEvent] {
        let startOfDay = calendar.startOfDay(for: startDate)
        return events
            .filter { calendar.startOfDay(for: $0.endDate) >= startOfDay }
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.startDate < $1.startDate
            }
            .prefix(limit)
            .map { $0 }
    }

    public func upcomingOccurrences(from startDate: Date, events: [CalendarEvent], limit: Int, horizonDays: Int = 90) -> [EventOccurrence] {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(byAdding: .day, value: horizonDays, to: start) ?? start
        let interval = DateInterval(start: start, end: end)
        let expander = RecurrenceExpander(calendar: calendar)
        return events
            .flatMap { expander.occurrences(for: $0, in: interval) }
            .filter { $0.endDate >= start }
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.startDate < $1.startDate
            }
            .prefix(limit)
            .map { $0 }
    }

    public func search(_ query: String, in events: [CalendarEvent]) -> [CalendarEvent] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.isEmpty == false else { return events }
        return events.filter { event in
            event.title.lowercased().contains(normalized) ||
            event.notes.lowercased().contains(normalized)
        }
    }

    public func deletePlan(for event: CalendarEvent) -> EventDeletePlan {
        let ids = event.notificationOffsetsDays.map { offset in
            "event-\(event.id.uuidString.lowercased())-offset-\(offset)"
        }
        return EventDeletePlan(eventID: event.id, notificationIdentifiers: ids)
    }
}
```

- [ ] **Step 5: Run tests**

```bash
swift test --filter RecurrenceExpanderTests
swift test --filter EventServiceTests
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MyMacCalendarCore/Services/RecurrenceExpander.swift Sources/MyMacCalendarCore/Services/EventService.swift Tests/MyMacCalendarCoreTests/RecurrenceExpanderTests.swift Tests/MyMacCalendarCoreTests/EventServiceTests.swift
git commit -m "feat: add recurrence and event service"
```

## Task 4: Holiday Fetch, Merge, and User Overrides

**Files:**
- Create: `Sources/MyMacCalendarCore/Services/HolidayService.swift`
- Create: `Tests/MyMacCalendarCoreTests/HolidayServiceTests.swift`

- [ ] **Step 1: Write holiday merge tests**

Create `Tests/MyMacCalendarCoreTests/HolidayServiceTests.swift`:

```swift
import XCTest
@testable import MyMacCalendarCore

final class HolidayServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testHiddenApiHolidayStaysHiddenAfterRefetch() throws {
        let newYear = HolidayImport(date: try date(2026, 1, 1), title: "New Year's Day", providerKey: "2026-01-01-New Year's Day")
        let hidden = HolidayRecord(date: try date(2026, 1, 1), title: "New Year's Day", source: .api, providerKey: "2026-01-01-New Year's Day", isHidden: true, year: 2026)

        let visible = HolidayMerger().merge(imports: [newYear], existing: [hidden], year: 2026)

        XCTAssertTrue(visible.isEmpty)
    }

    func testManualHolidayOverridesApiOnSameDate() throws {
        let api = HolidayImport(date: try date(2026, 5, 5), title: "Children's Day", providerKey: "2026-05-05-Children's Day")
        let manual = HolidayRecord(date: try date(2026, 5, 5), title: "어린이날 직접수정", source: .manual, year: 2026)

        let visible = HolidayMerger().merge(imports: [api], existing: [manual], year: 2026)

        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible[0].title, "어린이날 직접수정")
        XCTAssertEqual(visible[0].source, .manual)
    }

    func testNagerDecodeMapsLocalNameAndProviderKey() throws {
        let data = """
        [{"date":"2026-01-01","localName":"새해","name":"New Year's Day","countryCode":"KR","fixed":false,"global":true,"counties":null,"launchYear":null,"types":["Public"]}]
        """.data(using: .utf8)!

        let imports = try NagerHolidayDecoder().decode(data: data, calendar: calendar)

        XCTAssertEqual(imports.count, 1)
        XCTAssertEqual(imports[0].title, "새해")
        XCTAssertEqual(imports[0].providerKey, "2026-01-01-새해")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
swift test --filter HolidayServiceTests
```

Expected: build fails because `HolidayImport`, `HolidayMerger`, and `NagerHolidayDecoder` are not defined.

- [ ] **Step 3: Implement holiday service**

Create `Sources/MyMacCalendarCore/Services/HolidayService.swift`:

```swift
import Foundation

public struct HolidayImport: Equatable {
    public let date: Date
    public let title: String
    public let providerKey: String

    public init(date: Date, title: String, providerKey: String) {
        self.date = date
        self.title = title
        self.providerKey = providerKey
    }
}

private struct NagerHolidayDTO: Decodable {
    let date: String
    let localName: String
}

public struct NagerHolidayDecoder {
    public init() {}

    public func decode(data: Data, calendar: Calendar = .current) throws -> [HolidayImport] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return try JSONDecoder().decode([NagerHolidayDTO].self, from: data).compactMap { dto in
            guard let date = formatter.date(from: dto.date) else { return nil }
            return HolidayImport(date: calendar.startOfDay(for: date), title: dto.localName, providerKey: "\(dto.date)-\(dto.localName)")
        }
    }
}

public struct HolidayMerger {
    public init() {}

    public func merge(imports: [HolidayImport], existing: [HolidayRecord], year: Int) -> [HolidayRecord] {
        let hiddenKeys = Set(existing.filter { $0.source == .api && $0.isHidden }.map(\.providerKey))
        let manualByDate = Dictionary(grouping: existing.filter { $0.source == .manual && $0.year == year }, by: { dayKey($0.date) })
            .compactMapValues { $0.sorted { $0.updatedAt > $1.updatedAt }.first }

        var merged: [HolidayRecord] = []
        for item in imports where hiddenKeys.contains(item.providerKey) == false {
            let key = dayKey(item.date)
            if manualByDate[key] == nil {
                merged.append(HolidayRecord(date: item.date, title: item.title, source: .api, providerKey: item.providerKey, year: year))
            }
        }

        merged.append(contentsOf: manualByDate.values)
        return merged.sorted { $0.date < $1.date }
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

public struct HolidayService {
    private let session: URLSession
    private let decoder: NagerHolidayDecoder

    public init(session: URLSession = .shared, decoder: NagerHolidayDecoder = NagerHolidayDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    public func fetchKoreanHolidays(year: Int) async throws -> [HolidayImport] {
        let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/KR")!
        let (data, _) = try await session.data(from: url)
        return try decoder.decode(data: data, calendar: Calendar(identifier: .gregorian))
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter HolidayServiceTests
```

Expected: all holiday tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCalendarCore/Services/HolidayService.swift Tests/MyMacCalendarCoreTests/HolidayServiceTests.swift
git commit -m "feat: add holiday merge and overrides"
```

## Task 5: Notification Planning

**Files:**
- Create: `Sources/MyMacCalendarCore/Services/NotificationService.swift`
- Create: `Tests/MyMacCalendarCoreTests/NotificationServiceTests.swift`

- [ ] **Step 1: Write notification tests**

Create `Tests/MyMacCalendarCoreTests/NotificationServiceTests.swift`:

```swift
import XCTest
@testable import MyMacCalendarCore

final class NotificationServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testNotificationRequestsUseDefaultReminderTime() throws {
        let eventID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let event = CalendarEvent(
            id: eventID,
            title: "Codex 만료",
            startDate: try date(2026, 6, 30),
            endDate: try date(2026, 6, 30),
            notificationOffsetsDays: [7, 1, 0]
        )

        let planner = NotificationPlanner(calendar: calendar)
        let plans = planner.plans(for: event, defaultHour: 9, defaultMinute: 0, now: try date(2026, 6, 1))

        XCTAssertEqual(plans.map(\.identifier), [
            "event-22222222-2222-2222-2222-222222222222-offset-7",
            "event-22222222-2222-2222-2222-222222222222-offset-1",
            "event-22222222-2222-2222-2222-222222222222-offset-0"
        ])
        XCTAssertEqual(plans.map { calendar.component(.day, from: $0.fireDate) }, [23, 29, 30])
        XCTAssertTrue(plans.allSatisfy { calendar.component(.hour, from: $0.fireDate) == 9 })
    }

    func testPastNotificationsAreSkipped() throws {
        let event = CalendarEvent(
            title: "Tomorrow",
            startDate: try date(2026, 6, 26),
            endDate: try date(2026, 6, 26),
            notificationOffsetsDays: [7, 1, 0]
        )

        let plans = NotificationPlanner(calendar: calendar).plans(for: event, defaultHour: 9, defaultMinute: 0, now: try date(2026, 6, 25))

        XCTAssertEqual(plans.map(\.offsetDays), [0])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
swift test --filter NotificationServiceTests
```

Expected: build fails because `NotificationPlanner` is not defined.

- [ ] **Step 3: Implement notification planner and scheduler**

Create `Sources/MyMacCalendarCore/Services/NotificationService.swift`:

```swift
import Foundation
import UserNotifications

public struct NotificationPlan: Equatable {
    public let identifier: String
    public let eventID: UUID
    public let title: String
    public let fireDate: Date
    public let offsetDays: Int
}

public struct NotificationPlanner {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func plans(for event: CalendarEvent, defaultHour: Int, defaultMinute: Int, now: Date = Date()) -> [NotificationPlan] {
        event.notificationOffsetsDays
            .sorted(by: >)
            .compactMap { offset in
                guard let reminderDay = calendar.date(byAdding: .day, value: -offset, to: event.startDate) else { return nil }
                let components = calendar.dateComponents([.year, .month, .day], from: reminderDay)
                guard let fireDate = calendar.date(from: DateComponents(year: components.year, month: components.month, day: components.day, hour: defaultHour, minute: defaultMinute)) else { return nil }
                guard fireDate > now else { return nil }
                return NotificationPlan(
                    identifier: "event-\(event.id.uuidString.lowercased())-offset-\(offset)",
                    eventID: event.id,
                    title: event.title,
                    fireDate: fireDate,
                    offsetDays: offset
                )
            }
    }
}

public final class NotificationService {
    private let center: UNUserNotificationCenter
    private let planner: NotificationPlanner

    public init(center: UNUserNotificationCenter = .current(), planner: NotificationPlanner = NotificationPlanner()) {
        self.center = center
        self.planner = planner
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func schedule(event: CalendarEvent, defaultHour: Int, defaultMinute: Int) {
        let plans = planner.plans(for: event, defaultHour: defaultHour, defaultMinute: defaultMinute)
        center.removePendingNotificationRequests(withIdentifiers: event.notificationOffsetsDays.map {
            "event-\(event.id.uuidString.lowercased())-offset-\($0)"
        })
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.offsetDays == 0 ? "오늘 일정입니다." : "\(plan.offsetDays)일 전 알림입니다."
            content.sound = .default
            let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
            center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger))
        }
    }

    public func cancel(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter NotificationServiceTests
```

Expected: all notification tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCalendarCore/Services/NotificationService.swift Tests/MyMacCalendarCoreTests/NotificationServiceTests.swift
git commit -m "feat: add notification planning"
```

## Task 6: Quick Add Parser

**Files:**
- Create: `Sources/MyMacCalendarCore/Services/QuickAddParser.swift`
- Create: `Tests/MyMacCalendarCoreTests/QuickAddParserTests.swift`

- [ ] **Step 1: Write parser tests**

Create `Tests/MyMacCalendarCoreTests/QuickAddParserTests.swift`:

```swift
import XCTest
@testable import MyMacCalendarCore

final class QuickAddParserTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testNumericSlashDate() throws {
        let parser = QuickAddParser(calendar: calendar)
        let result = parser.parse("6/30 codex 만료", now: try date(2026, 6, 25))

        XCTAssertEqual(result.title, "codex 만료")
        XCTAssertEqual(calendar.component(.month, from: result.startDate), 6)
        XCTAssertEqual(calendar.component(.day, from: result.startDate), 30)
        XCTAssertFalse(result.needsConfirmation)
    }

    func testIsoDate() throws {
        let parser = QuickAddParser(calendar: calendar)
        let result = parser.parse("2026-12-25 여행", now: try date(2026, 6, 25))

        XCTAssertEqual(result.title, "여행")
        XCTAssertEqual(calendar.component(.year, from: result.startDate), 2026)
        XCTAssertEqual(calendar.component(.month, from: result.startDate), 12)
        XCTAssertEqual(calendar.component(.day, from: result.startDate), 25)
    }

    func testNextMondayKoreanPhrase() throws {
        let parser = QuickAddParser(calendar: calendar)
        let result = parser.parse("다음주 월요일 병원", now: try date(2026, 6, 25))

        XCTAssertEqual(result.title, "병원")
        XCTAssertEqual(calendar.component(.month, from: result.startDate), 6)
        XCTAssertEqual(calendar.component(.day, from: result.startDate), 29)
    }

    func testAmbiguousInputNeedsConfirmation() throws {
        let parser = QuickAddParser(calendar: calendar)
        let result = parser.parse("회의", now: try date(2026, 6, 25))

        XCTAssertEqual(result.title, "회의")
        XCTAssertTrue(result.needsConfirmation)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
swift test --filter QuickAddParserTests
```

Expected: build fails because `QuickAddParser` is not defined.

- [ ] **Step 3: Implement parser**

Create `Sources/MyMacCalendarCore/Services/QuickAddParser.swift`:

```swift
import Foundation

public struct QuickAddResult: Equatable {
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let needsConfirmation: Bool
}

public struct QuickAddParser {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func parse(_ input: String, now: Date = Date()) -> QuickAddResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = parseISO(trimmed) ?? parseSlash(trimmed, now: now) ?? parseNextWeekday(trimmed, now: now) {
            return parsed
        }
        let fallback = calendar.startOfDay(for: now)
        return QuickAddResult(title: trimmed, startDate: fallback, endDate: fallback, needsConfirmation: true)
    }

    private func parseISO(_ input: String) -> QuickAddResult? {
        let pattern = #"^(\d{4})-(\d{1,2})-(\d{1,2})\s+(.+)$"#
        guard let match = input.firstMatch(pattern: pattern) else { return nil }
        guard let year = Int(match[1]), let month = Int(match[2]), let day = Int(match[3]) else { return nil }
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return QuickAddResult(title: match[4], startDate: calendar.startOfDay(for: date), endDate: calendar.startOfDay(for: date), needsConfirmation: false)
    }

    private func parseSlash(_ input: String, now: Date) -> QuickAddResult? {
        let pattern = #"^(\d{1,2})/(\d{1,2})\s+(.+)$"#
        guard let match = input.firstMatch(pattern: pattern) else { return nil }
        guard let month = Int(match[1]), let day = Int(match[2]) else { return nil }
        let year = calendar.component(.year, from: now)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return QuickAddResult(title: match[3], startDate: calendar.startOfDay(for: date), endDate: calendar.startOfDay(for: date), needsConfirmation: false)
    }

    private func parseNextWeekday(_ input: String, now: Date) -> QuickAddResult? {
        let weekdays = ["일요일": 1, "월요일": 2, "화요일": 3, "수요일": 4, "목요일": 5, "금요일": 6, "토요일": 7]
        for (word, weekday) in weekdays {
            let prefix = "다음주 \(word) "
            guard input.hasPrefix(prefix) else { continue }
            let title = String(input.dropFirst(prefix.count))
            let startOfToday = calendar.startOfDay(for: now)
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: startOfToday) else { return nil }
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: nextWeek)
            components.weekday = weekday
            guard let date = calendar.date(from: components) else { return nil }
            return QuickAddResult(title: title, startDate: calendar.startOfDay(for: date), endDate: calendar.startOfDay(for: date), needsConfirmation: false)
        }
        return nil
    }
}

private extension String {
    func firstMatch(pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: nsRange) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: self) else { return nil }
            return String(self[range])
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter QuickAddParserTests
```

Expected: all parser tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCalendarCore/Services/QuickAddParser.swift Tests/MyMacCalendarCoreTests/QuickAddParserTests.swift
git commit -m "feat: add quick add parser"
```

## Task 7: SwiftData Store and Settings

**Files:**
- Create: `Sources/MyMacCalendarCore/Models/AppSettings.swift`
- Create: `Sources/MyMacCalendarCore/Stores/CalendarStore.swift`
- Create: `Sources/MyMacCalendarCore/Stores/SettingsStore.swift`
- Create: `Tests/MyMacCalendarCoreTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write settings tests**

Create `Tests/MyMacCalendarCoreTests/SettingsStoreTests.swift`:

```swift
import XCTest
import SwiftData
@testable import MyMacCalendarCore

final class SettingsStoreTests: XCTestCase {
    func testDefaultSettings() throws {
        let settings = AppSettings()

        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertTrue(settings.showMenuBar)
        XCTAssertTrue(settings.floatingWidgetEnabled)
        XCTAssertTrue(settings.floatingWidgetAlwaysOnTop)
        XCTAssertEqual(settings.defaultReminderHour, 9)
        XCTAssertEqual(settings.defaultReminderMinute, 0)
    }

    func testStoreCreatesSettingsWhenMissing() throws {
        let container = try CalendarStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let store = SettingsStore(context: context)

        let settings = try store.load()

        XCTAssertEqual(settings.defaultReminderHour, 9)
        XCTAssertTrue(settings.showMenuBar)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
swift test --filter SettingsStoreTests
```

Expected: build fails because `AppSettings`, `CalendarStore`, and `SettingsStore` are not defined.

- [ ] **Step 3: Implement store and settings**

Create `Sources/MyMacCalendarCore/Models/AppSettings.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class AppSettings {
    @Attribute(.unique) public var id: String
    public var launchAtLogin: Bool
    public var showMenuBar: Bool
    public var floatingWidgetEnabled: Bool
    public var floatingWidgetAlwaysOnTop: Bool
    public var floatingWidgetOpacity: Double
    public var floatingWidgetVisibleCount: Int
    public var defaultReminderHour: Int
    public var defaultReminderMinute: Int
    public var theme: String
    public var calendarDensity: String

    public init(
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
```

Create `Sources/MyMacCalendarCore/Stores/CalendarStore.swift`:

```swift
import Foundation
import SwiftData

public enum CalendarStore {
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            CalendarEvent.self,
            HolidayRecord.self,
            AppSettings.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    public static func makeInMemoryContainer() throws -> ModelContainer {
        try makeContainer(inMemory: true)
    }
}
```

Create `Sources/MyMacCalendarCore/Stores/SettingsStore.swift`:

```swift
import Foundation
import SwiftData

public final class SettingsStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func load() throws -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>(predicate: #Predicate { $0.id == "default" })
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter SettingsStoreTests
```

Expected: all settings tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCalendarCore/Models/AppSettings.swift Sources/MyMacCalendarCore/Stores Tests/MyMacCalendarCoreTests/SettingsStoreTests.swift
git commit -m "feat: add SwiftData store and settings"
```

## Task 8: Main Window UI

**Files:**
- Modify: `Sources/MyMacCalendar/App/MyMacCalendarApp.swift`
- Modify: `Sources/MyMacCalendar/Views/MainWindowView.swift`
- Create: `Sources/MyMacCalendar/Views/MonthGridView.swift`
- Create: `Sources/MyMacCalendar/Views/AgendaPanelView.swift`

- [ ] **Step 1: Inject SwiftData container into app**

Replace `Sources/MyMacCalendar/App/MyMacCalendarApp.swift` with:

```swift
import SwiftUI
import SwiftData
import MyMacCalendarCore

@main
struct MyMacCalendarApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try CalendarStore.makeContainer()
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup(AppVersion.name) {
            MainWindowView()
                .modelContainer(container)
        }
        .defaultSize(width: 1100, height: 720)
    }
}
```

- [ ] **Step 2: Build main shell**

Replace `Sources/MyMacCalendar/Views/MainWindowView.swift` with:

```swift
import SwiftUI
import SwiftData
import MyMacCalendarCore

struct MainWindowView: View {
    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]
    @Query(sort: \HolidayRecord.date) private var holidays: [HolidayRecord]
    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    @State private var searchText = ""
    @State private var showingEditor = false

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                header
                MonthGridView(displayedMonth: displayedMonth, selectedDate: $selectedDate, events: filteredEvents, holidays: holidays)
            }
            .padding(20)
            .frame(minWidth: 720)
        } detail: {
            AgendaPanelView(selectedDate: selectedDate, events: filteredEvents)
                .frame(minWidth: 320)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Today") {
                    displayedMonth = Date()
                    selectedDate = Date()
                }
                Button {
                    showingEditor = true
                } label: {
                    Label("New Event", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            Text("Event editor added in Task 9")
                .frame(width: 420, height: 240)
        }
    }

    private var header: some View {
        HStack {
            Button {
                displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.left")
            }

            Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                .font(.title2.weight(.semibold))
                .frame(minWidth: 180)

            Button {
                displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.right")
            }

            Spacer()

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
    }

    private var filteredEvents: [CalendarEvent] {
        EventService().search(searchText, in: events)
    }
}
```

- [ ] **Step 3: Add month grid view**

Create `Sources/MyMacCalendar/Views/MonthGridView.swift`:

```swift
import SwiftUI
import MyMacCalendarCore

struct MonthGridView: View {
    let displayedMonth: Date
    @Binding var selectedDate: Date
    let events: [CalendarEvent]
    let holidays: [HolidayRecord]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(symbol == "Sun" ? .red : symbol == "Sat" ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(cells, id: \.date) { cell in
                    Button {
                        selectedDate = cell.date
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(cell.day)")
                                .font(.system(size: 15, weight: Calendar.current.isDate(cell.date, inSameDayAs: selectedDate) ? .bold : .medium))
                                .foregroundStyle(textColor(for: cell))
                            Spacer()
                            HStack(spacing: 3) {
                                ForEach(markers(for: cell.date).prefix(3), id: \.self) { color in
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 5, height: 5)
                                }
                            }
                        }
                        .padding(8)
                        .frame(minHeight: 86, alignment: .topLeading)
                        .background(Calendar.current.isDate(cell.date, inSameDayAs: selectedDate) ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(cell.isInDisplayedMonth ? 1 : 0.38)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var cells: [CalendarDayCell] {
        let components = Calendar.current.dateComponents([.year, .month], from: displayedMonth)
        return (try? CalendarGridBuilder().makeMonthGrid(year: components.year ?? 2026, month: components.month ?? 1)) ?? []
    }

    private func markers(for date: Date) -> [String] {
        events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) }.map(\.colorHex)
    }

    private func textColor(for cell: CalendarDayCell) -> Color {
        if holidays.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: cell.date) && $0.isHidden == false }) || cell.isSunday {
            return .red
        }
        if cell.isSaturday {
            return .blue
        }
        return .primary
    }
}

private extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: value).scanHexInt64(&int)
        self.init(
            red: Double((int >> 16) & 0xFF) / 255.0,
            green: Double((int >> 8) & 0xFF) / 255.0,
            blue: Double(int & 0xFF) / 255.0
        )
    }
}
```

- [ ] **Step 4: Add agenda panel**

Create `Sources/MyMacCalendar/Views/AgendaPanelView.swift`:

```swift
import SwiftUI
import MyMacCalendarCore

struct AgendaPanelView: View {
    let selectedDate: Date
    let events: [CalendarEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(selectedDate.formatted(.dateTime.year().month().day().weekday()))
                .font(.headline)

            GroupBox("Selected Day") {
                list(eventsForSelectedDate)
            }

            GroupBox("Upcoming") {
                occurrenceList(upcomingOccurrences)
            }

            Spacer()
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var eventsForSelectedDate: [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: selectedDate) }
    }

    private var upcomingOccurrences: [EventOccurrence] {
        EventService().upcomingOccurrences(from: selectedDate, events: events, limit: 8)
    }

    private func list(_ items: [CalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if items.isEmpty {
                Text("No events")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.id) { event in
                    HStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading) {
                            Text(event.title)
                                .font(.body.weight(.medium))
                            Text(event.startDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func occurrenceList(_ items: [EventOccurrence]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if items.isEmpty {
                Text("No events")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.startDate) { occurrence in
                    HStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading) {
                            Text(occurrence.title)
                                .font(.body.weight(.medium))
                            Text(occurrence.startDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 5: Compile app**

```bash
swift build
```

Expected: build exits `0`.

- [ ] **Step 6: Commit**

```bash
git add Sources/MyMacCalendar
git commit -m "feat: add main calendar window"
```

## Task 9: Event Editor, Delete, and Quick Add UI

**Files:**
- Modify: `Sources/MyMacCalendar/Views/MainWindowView.swift`
- Modify: `Sources/MyMacCalendar/Views/AgendaPanelView.swift`
- Create: `Sources/MyMacCalendar/Views/EventEditorView.swift`
- Create: `Sources/MyMacCalendar/Views/QuickAddView.swift`

- [ ] **Step 1: Add event editor view**

Create `Sources/MyMacCalendar/Views/EventEditorView.swift`:

```swift
import SwiftUI
import SwiftData
import MyMacCalendarCore

struct EventEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let event: CalendarEvent?
    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var notes: String
    @State private var recurrence: EventRecurrence
    @State private var notificationOffsets: Set<Int>
    @State private var showingDeleteConfirmation = false

    init(event: CalendarEvent? = nil, defaultDate: Date = Date()) {
        self.event = event
        _title = State(initialValue: event?.title ?? "")
        _startDate = State(initialValue: event?.startDate ?? defaultDate)
        _endDate = State(initialValue: event?.endDate ?? defaultDate)
        _notes = State(initialValue: event?.notes ?? "")
        _recurrence = State(initialValue: event?.recurrence ?? .none)
        _notificationOffsets = State(initialValue: Set(event?.notificationOffsetsDays ?? [1]))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(event == nil ? "New Event" : "Edit Event")
                .font(.title3.weight(.semibold))

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            DatePicker("Start", selection: $startDate, displayedComponents: .date)
            DatePicker("End", selection: $endDate, displayedComponents: .date)

            Picker("Repeat", selection: $recurrence) {
                Text("None").tag(EventRecurrence.none)
                Text("Weekly").tag(EventRecurrence.weekly)
                Text("Monthly").tag(EventRecurrence.monthly)
                Text("Yearly").tag(EventRecurrence.yearly)
            }

            VStack(alignment: .leading) {
                Text("Notifications")
                    .font(.subheadline.weight(.semibold))
                ForEach([7, 2, 1, 0], id: \.self) { offset in
                    Toggle(label(for: offset), isOn: Binding(
                        get: { notificationOffsets.contains(offset) },
                        set: { isOn in
                            if isOn { notificationOffsets.insert(offset) } else { notificationOffsets.remove(offset) }
                        }
                    ))
                }
            }

            TextEditor(text: $notes)
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))

            HStack {
                if event != nil {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .confirmationDialog("Delete this event?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(recurrence == .none ? "This event will be removed." : "The entire repeating series will be removed.")
        }
    }

    private func label(for offset: Int) -> String {
        offset == 0 ? "On the day" : "\(offset) days before"
    }

    private func save() {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let event {
            event.title = normalizedTitle
            event.startDate = startDate
            event.endDate = endDate
            event.notes = notes
            event.recurrence = recurrence
            event.notificationOffsetsDays = notificationOffsets.sorted(by: >)
            event.updatedAt = Date()
        } else {
            modelContext.insert(CalendarEvent(title: normalizedTitle, startDate: startDate, endDate: endDate, notes: notes, recurrence: recurrence, notificationOffsetsDays: notificationOffsets.sorted(by: >)))
        }
        try? modelContext.save()
        dismiss()
    }

    private func delete() {
        if let event {
            modelContext.delete(event)
            try? modelContext.save()
        }
        dismiss()
    }
}
```

- [ ] **Step 2: Add quick add view**

Create `Sources/MyMacCalendar/Views/QuickAddView.swift`:

```swift
import SwiftUI
import SwiftData
import MyMacCalendarCore

struct QuickAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var parsed: QuickAddResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Add")
                .font(.title3.weight(.semibold))
            TextField("6/30 codex 만료", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(parse)
            if let parsed {
                GroupBox("Preview") {
                    VStack(alignment: .leading) {
                        Text(parsed.title)
                            .font(.headline)
                        Text(parsed.startDate.formatted(date: .complete, time: .omitted))
                            .foregroundStyle(.secondary)
                        if parsed.needsConfirmation {
                            Text("Date needs confirmation.")
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsed == nil)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func parse() {
        parsed = QuickAddParser().parse(input)
    }

    private func save() {
        let result = parsed ?? QuickAddParser().parse(input)
        modelContext.insert(CalendarEvent(title: result.title, startDate: result.startDate, endDate: result.endDate))
        try? modelContext.save()
        dismiss()
    }
}
```

- [ ] **Step 3: Wire sheets from main window**

Modify `Sources/MyMacCalendar/Views/MainWindowView.swift`:

```swift
// Add state:
@State private var showingQuickAdd = false

// Add toolbar button:
Button {
    showingQuickAdd = true
} label: {
    Label("Quick Add", systemImage: "bolt")
}

// Replace sheet block with two sheets:
.sheet(isPresented: $showingEditor) {
    EventEditorView(defaultDate: selectedDate)
}
.sheet(isPresented: $showingQuickAdd) {
    QuickAddView()
}
```

- [ ] **Step 4: Compile app**

```bash
swift build
```

Expected: build exits `0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCalendar/Views
git commit -m "feat: add event editor and quick add"
```

## Task 10: Settings and Holiday Management UI

**Files:**
- Modify: `Sources/MyMacCalendar/App/MyMacCalendarApp.swift`
- Create: `Sources/MyMacCalendar/Views/SettingsView.swift`

- [ ] **Step 1: Add settings scene**

Modify `Sources/MyMacCalendar/App/MyMacCalendarApp.swift` scene body:

```swift
WindowGroup(AppVersion.name) {
    MainWindowView()
        .modelContainer(container)
}
.defaultSize(width: 1100, height: 720)

Settings {
    SettingsView()
        .modelContainer(container)
}
```

- [ ] **Step 2: Implement settings view**

Create `Sources/MyMacCalendar/Views/SettingsView.swift`:

```swift
import SwiftUI
import SwiftData
import MyMacCalendarCore

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \HolidayRecord.date) private var holidays: [HolidayRecord]
    @State private var selectedTab = "general"
    @State private var newHolidayTitle = ""
    @State private var newHolidayDate = Date()

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            widgetTab
                .tabItem { Label("Widget", systemImage: "rectangle.on.rectangle") }
                .tag("widget")
            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag("notifications")
            holidaysTab
                .tabItem { Label("Holidays", systemImage: "calendar.badge.exclamationmark") }
                .tag("holidays")
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag("appearance")
            dataTab
                .tabItem { Label("Data", systemImage: "externaldrive") }
                .tag("data")
        }
        .padding(20)
        .frame(width: 680, height: 480)
        .onAppear { ensureSettings() }
    }

    private var settings: AppSettings {
        if let existing = settingsRows.first { return existing }
        let created = AppSettings()
        modelContext.insert(created)
        return created
    }

    private var generalTab: some View {
        Form {
            Toggle("Mac start auto-run", isOn: binding(\.launchAtLogin))
            Toggle("Show menu bar icon", isOn: binding(\.showMenuBar))
        }
    }

    private var widgetTab: some View {
        Form {
            Toggle("Show floating widget", isOn: binding(\.floatingWidgetEnabled))
            Toggle("Always on top", isOn: binding(\.floatingWidgetAlwaysOnTop))
            Slider(value: binding(\.floatingWidgetOpacity), in: 0.4...1.0) {
                Text("Opacity")
            }
            Stepper("Visible events: \(settings.floatingWidgetVisibleCount)", value: binding(\.floatingWidgetVisibleCount), in: 1...12)
        }
    }

    private var notificationsTab: some View {
        Form {
            Stepper("Hour: \(settings.defaultReminderHour)", value: binding(\.defaultReminderHour), in: 0...23)
            Stepper("Minute: \(settings.defaultReminderMinute)", value: binding(\.defaultReminderMinute), in: 0...59)
        }
    }

    private var holidaysTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DatePicker("Date", selection: $newHolidayDate, displayedComponents: .date)
                TextField("Holiday name", text: $newHolidayTitle)
                Button("Add") { addManualHoliday() }
                    .disabled(newHolidayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            List {
                ForEach(holidays.filter { $0.isHidden == false }, id: \.id) { holiday in
                    HStack {
                        Text(holiday.date.formatted(date: .abbreviated, time: .omitted))
                        Text(holiday.title)
                        Spacer()
                        Text(holiday.source.rawValue.uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            hideOrDelete(holiday)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var appearanceTab: some View {
        Form {
            Picker("Theme", selection: binding(\.theme)) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            Picker("Calendar density", selection: binding(\.calendarDensity)) {
                Text("Comfortable").tag("comfortable")
                Text("Compact").tag("compact")
            }
        }
    }

    private var dataTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data is stored locally using SwiftData.")
            Text("Backup and restore are reserved for a later version.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func ensureSettings() {
        if settingsRows.isEmpty {
            modelContext.insert(AppSettings())
            try? modelContext.save()
        }
    }

    private func addManualHoliday() {
        let year = Calendar.current.component(.year, from: newHolidayDate)
        modelContext.insert(HolidayRecord(date: newHolidayDate, title: newHolidayTitle, source: .manual, year: year))
        newHolidayTitle = ""
        try? modelContext.save()
    }

    private func hideOrDelete(_ holiday: HolidayRecord) {
        if holiday.source == .api {
            holiday.isHidden = true
        } else {
            modelContext.delete(holiday)
        }
        try? modelContext.save()
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: {
                settings[keyPath: keyPath] = $0
                try? modelContext.save()
            }
        )
    }
}
```

- [ ] **Step 3: Compile app**

```bash
swift build
```

Expected: build exits `0`.

- [ ] **Step 4: Commit**

```bash
git add Sources/MyMacCalendar/App/MyMacCalendarApp.swift Sources/MyMacCalendar/Views/SettingsView.swift
git commit -m "feat: add settings and holiday management"
```

## Task 11: Menu Bar and Floating Widget

**Files:**
- Create: `Sources/MyMacCalendar/App/AppDelegate.swift`
- Create: `Sources/MyMacCalendar/Controllers/MenuBarController.swift`
- Create: `Sources/MyMacCalendar/Controllers/FloatingWidgetController.swift`
- Create: `Sources/MyMacCalendar/Views/FloatingWidgetView.swift`
- Modify: `Sources/MyMacCalendar/App/MyMacCalendarApp.swift`

- [ ] **Step 1: Add floating widget view**

Create `Sources/MyMacCalendar/Views/FloatingWidgetView.swift`:

```swift
import SwiftUI
import MyMacCalendarCore

struct FloatingWidgetView: View {
    let events: [CalendarEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming")
                .font(.headline)
            ForEach(events.prefix(5), id: \.id) { event in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isToday(event) ? Color.red : Color.accentColor)
                        .frame(width: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(event.startDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func isToday(_ event: CalendarEvent) -> Bool {
        Calendar.current.isDateInToday(event.startDate)
    }
}
```

- [ ] **Step 2: Add controllers**

Create `Sources/MyMacCalendar/Controllers/FloatingWidgetController.swift`:

```swift
import AppKit
import SwiftUI
import MyMacCalendarCore

final class FloatingWidgetController {
    private var window: NSWindow?

    func show(events: [CalendarEvent]) {
        if window == nil {
            let hosting = NSHostingController(rootView: FloatingWidgetView(events: events))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.styleMask = [.borderless]
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = .floating
            newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newWindow.setFrame(NSRect(x: 80, y: 600, width: 280, height: 260), display: true)
            window = newWindow
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }
}
```

Create `Sources/MyMacCalendar/Controllers/MenuBarController.swift`:

```swift
import AppKit

final class MenuBarController {
    private var statusItem: NSStatusItem?
    var onOpenMainWindow: (() -> Void)?
    var onToggleWidget: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "MyMacCalendar")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Calendar", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show or Hide Widget", action: #selector(toggleWidget), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
    }

    @objc private func openMainWindow() {
        onOpenMainWindow?()
    }

    @objc private func toggleWidget() {
        onToggleWidget?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}
```

- [ ] **Step 3: Add app delegate**

Create `Sources/MyMacCalendar/App/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MenuBarController()
    private let floatingWidgetController = FloatingWidgetController()
    private var widgetVisible = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.onOpenMainWindow = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        menuBarController.onToggleWidget = { [weak self] in
            self?.toggleWidget()
        }
        menuBarController.onOpenSettings = {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        menuBarController.install()
    }

    private func toggleWidget() {
        if widgetVisible {
            floatingWidgetController.hide()
            widgetVisible = false
        } else {
            floatingWidgetController.show(events: [])
            widgetVisible = true
        }
    }
}
```

- [ ] **Step 4: Wire app delegate**

Modify `Sources/MyMacCalendar/App/MyMacCalendarApp.swift`:

```swift
@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
```

Place the property inside `MyMacCalendarApp`.

- [ ] **Step 5: Compile app**

```bash
swift build
```

Expected: build exits `0`.

- [ ] **Step 6: Commit**

```bash
git add Sources/MyMacCalendar/App Sources/MyMacCalendar/Controllers Sources/MyMacCalendar/Views/FloatingWidgetView.swift
git commit -m "feat: add menu bar and floating widget"
```

## Task 12: Build Bundle and Verification

**Files:**
- Create: `scripts/build_app.sh`
- Create: `README.md`

- [ ] **Step 1: Add app bundle script**

Create `scripts/build_app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/build/MyMacCalendar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$BUILD_DIR/MyMacCalendar" "$MACOS_DIR/MyMacCalendar"
cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MyMacCalendar</string>
    <key>CFBundleIdentifier</key>
    <string>local.mymaccalendar.app</string>
    <key>CFBundleName</key>
    <string>MyMacCalendar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "$APP_DIR"
```

- [ ] **Step 2: Add README**

Create `README.md`:

```markdown
# MyMacCalendar

Local-first macOS calendar app for all-day events, simple recurrence, editable holidays, notifications, and a floating upcoming-events widget.

## Requirements

- macOS 14 or later
- Xcode 16.4 or compatible Swift 6 toolchain

## Development

```bash
swift test
swift build
```

## Build App Bundle

```bash
chmod +x scripts/build_app.sh
./scripts/build_app.sh
open build/MyMacCalendar.app
```
```

- [ ] **Step 3: Run full verification**

```bash
chmod +x scripts/build_app.sh
swift test
swift build
./scripts/build_app.sh
```

Expected:

- `swift test` exits `0`.
- `swift build` exits `0`.
- `./scripts/build_app.sh` prints `/Users/biglol/Desktop/practice/MyMacCalendar/build/MyMacCalendar.app`.

- [ ] **Step 4: Manual UI verification**

Run:

```bash
open build/MyMacCalendar.app
```

Verify:

- Main window opens.
- Monthly calendar grid renders.
- Right agenda panel renders.
- Settings window opens from app menu.
- Menu bar item appears.
- Floating widget can be toggled from the menu bar.
- New event sheet opens.
- Quick add sheet opens.

- [ ] **Step 5: Commit**

```bash
git add scripts/build_app.sh README.md
git commit -m "chore: add app bundle build flow"
```

## Spec Coverage Review

- All-day event create/edit/delete: Task 9.
- Weekly/monthly/yearly recurrence: Task 3.
- Calendar month grid and agenda: Tasks 2 and 8.
- Search logic and UI wiring: Tasks 3 and 8.
- Quick add: Tasks 6 and 9.
- Notifications: Task 5.
- Editable holiday data and hidden API rows: Tasks 4 and 10.
- Floating always-on-top widget: Task 11.
- Menu bar app surface: Task 11.
- Settings tabs: Task 10.
- Local SwiftData storage: Task 7.
- macOS 14+ SwiftUI app bundle: Tasks 1 and 12.

## Execution Order

Execute tasks in numerical order. Commit after each task. Run the listed verification command before every commit.
