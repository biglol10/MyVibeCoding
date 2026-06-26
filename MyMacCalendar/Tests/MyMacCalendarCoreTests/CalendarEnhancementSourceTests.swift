import XCTest

final class CalendarEnhancementSourceTests: XCTestCase {
    func testMonthOverflowOpensDayPopoverAfterShowingTwoItems() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/MonthGridView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("@State private var overflowDate: Date?"))
        XCTAssertTrue(source.contains("static let visibleEntryLimit = 2"))
        XCTAssertTrue(source.contains("Button {"))
        XCTAssertTrue(source.contains("selectedDate = cell.date"))
        XCTAssertTrue(source.contains("overflowDate = cell.date"))
        XCTAssertTrue(source.contains(".popover(isPresented: overflowPopoverBinding(for: cell.date))"))
        XCTAssertTrue(source.contains("DayOverflowPopover"))
    }

    func testSelectedDayPanelIsConnectedToMainWindow() throws {
        let mainSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/MainWindowView.swift"), encoding: .utf8)
        let panelSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/DayAgendaPanelView.swift"), encoding: .utf8)

        XCTAssertTrue(mainSource.contains("DayAgendaPanelView("))
        XCTAssertTrue(mainSource.contains("selectedDate: selectedDate"))
        XCTAssertTrue(mainSource.contains("onCreateEvent: { date in"))
        XCTAssertTrue(panelSource.contains("struct DayAgendaPanelView: View"))
        XCTAssertTrue(panelSource.contains("RecurrenceExpander(calendar: calendar)"))
        XCTAssertTrue(panelSource.contains("HolidayRecord"))
        XCTAssertTrue(panelSource.contains("onSelectEvent(event)"))
    }

    func testFloatingWidgetOverflowCanOpenFullUpcomingList() throws {
        let viewSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/FloatingWidgetView.swift"), encoding: .utf8)
        let controllerSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Controllers/FloatingWidgetController.swift"), encoding: .utf8)

        XCTAssertTrue(viewSource.contains("let onShowAll: () -> Void"))
        XCTAssertTrue(viewSource.contains("Button { onShowAll() }"))
        XCTAssertTrue(viewSource.contains("Text(\"+\\(overflowCount)개\")"))
        XCTAssertTrue(controllerSource.contains("private var listWindow: NSWindow?"))
        XCTAssertTrue(controllerSource.contains("showAll(occurrences: [EventOccurrence]"))
        XCTAssertTrue(controllerSource.contains("FloatingWidgetAllEventsView"))
    }

    func testFloatingWidgetPositionIsPersistedAfterDrag() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Controllers/FloatingWidgetController.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("FloatingWidgetPositionStore"))
        XCTAssertTrue(source.contains("NSWindow.didMoveNotification"))
        XCTAssertTrue(source.contains("UserDefaults.standard.set"))
        XCTAssertTrue(source.contains("FloatingWidgetPositionStore.loadFrame()"))
        XCTAssertTrue(source.contains("FloatingWidgetPositionStore.saveFrame"))
    }

    func testMenuBarHasQuickAddAndWorkingSettingsCommands() throws {
        let menuSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Controllers/MenuBarController.swift"), encoding: .utf8)
        let appDelegateSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/App/AppDelegate.swift"), encoding: .utf8)
        let mainSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/MainWindowView.swift"), encoding: .utf8)

        XCTAssertTrue(menuSource.contains("var onQuickAdd: (() -> Void)?"))
        XCTAssertTrue(menuSource.contains("NSMenuItem(title: \"빠른 추가\""))
        XCTAssertTrue(menuSource.contains("#selector(openQuickAdd)"))
        XCTAssertTrue(appDelegateSource.contains(".openQuickAddSheet"))
        XCTAssertTrue(appDelegateSource.contains(".openSettingsSheet"))
        XCTAssertTrue(mainSource.contains("NotificationCenter.default.publisher(for: .openQuickAddSheet)"))
        XCTAssertTrue(mainSource.contains("NotificationCenter.default.publisher(for: .openSettingsSheet)"))
    }

    func testEventCategoriesDriveDefaultColors() throws {
        let modelSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendarCore/Models/CalendarEvent.swift"), encoding: .utf8)
        let editorSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/EventEditorView.swift"), encoding: .utf8)

        XCTAssertTrue(modelSource.contains("public enum EventCategory"))
        XCTAssertTrue(modelSource.contains("public var categoryRaw: String"))
        XCTAssertTrue(modelSource.contains("public var category: EventCategory"))
        XCTAssertTrue(editorSource.contains("@State private var category: EventCategory"))
        XCTAssertTrue(editorSource.contains("Picker(\"카테고리\""))
        XCTAssertTrue(editorSource.contains("event.colorHex = category.colorHex"))
        XCTAssertTrue(editorSource.contains("category: category"))
    }

    private func sourcePath(_ relativePath: String) -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .path
    }
}
