import Foundation
import XCTest

final class CalendarSearchSourceTests: XCTestCase {
    func testMainWindowConnectsSearchFieldAndResultSelection() throws {
        let source = try source("Sources/MyMacCalendar/Views/MainWindowView.swift")

        XCTAssertTrue(source.contains("@State private var searchQuery = \"\""))
        XCTAssertTrue(source.contains("@FocusState private var isSearchFocused: Bool"))
        XCTAssertTrue(source.contains("CalendarSearchField("))
        XCTAssertTrue(source.contains("CalendarSearchResultsView("))
        XCTAssertTrue(source.contains("EventService().search(searchQuery, in: events)"))
        XCTAssertTrue(source.contains("selectedDate = event.startDate"))
        XCTAssertTrue(source.contains("displayedMonth = event.startDate"))
        XCTAssertTrue(source.contains("activeSheet = .editEvent(event)"))
    }

    func testSearchViewsProvideClearEmptyAndTruncatedResultStates() throws {
        let relativePath = "Sources/MyMacCalendar/Views/CalendarSearchView.swift"
        let path = sourcePath(relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "Missing \(relativePath)")
        guard FileManager.default.fileExists(atPath: path) else { return }
        let source = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(source.contains("TextField(\"검색\""))
        XCTAssertTrue(source.contains("Image(systemName: \"magnifyingglass\")"))
        XCTAssertTrue(source.contains("Image(systemName: \"xmark.circle.fill\")"))
        XCTAssertTrue(source.contains("Text(\"검색 결과 없음\")"))
        XCTAssertTrue(source.contains("Text(\"검색 결과\")"))
        XCTAssertTrue(source.contains(".truncationMode(.tail)"))
        XCTAssertTrue(source.contains("onSelect(event)"))
    }

    func testCommandFFocusesSearchAndEscapeClearsIt() throws {
        let appSource = try source("Sources/MyMacCalendar/App/MyMacCalendarApp.swift")
        let notificationSource = try source("Sources/MyMacCalendar/App/AppCommandNotifications.swift")
        let mainSource = try source("Sources/MyMacCalendar/Views/MainWindowView.swift")
        let searchViewPath = sourcePath("Sources/MyMacCalendar/Views/CalendarSearchView.swift")

        XCTAssertTrue(appSource.contains("CommandGroup(after: .pasteboard)"))
        XCTAssertTrue(appSource.contains(".keyboardShortcut(\"f\", modifiers: .command)"))
        XCTAssertTrue(notificationSource.contains("focusCalendarSearch"))
        XCTAssertTrue(mainSource.contains("NotificationCenter.default.publisher(for: .focusCalendarSearch)"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: searchViewPath))
        guard FileManager.default.fileExists(atPath: searchViewPath) else { return }
        let searchSource = try String(contentsOfFile: searchViewPath, encoding: .utf8)
        XCTAssertTrue(searchSource.contains(".onExitCommand"))
        XCTAssertTrue(searchSource.contains("query = \"\""))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOfFile: sourcePath(relativePath), encoding: .utf8)
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
