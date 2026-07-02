import XCTest

final class FloatingWidgetSourceTests: XCTestCase {
    func testFloatingWidgetWindowCanBeDraggedByItsBackground() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Controllers/FloatingWidgetController.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("newWindow.isMovableByWindowBackground = true"))
        XCTAssertTrue(source.contains("FloatingWidgetWindow: NSWindow"))
        XCTAssertTrue(source.contains("FloatingWidgetHostingView: NSHostingView<FloatingWidgetView>"))
        XCTAssertTrue(source.contains("override var mouseDownCanMoveWindow: Bool"))
        XCTAssertTrue(source.contains("override func sendEvent(_ event: NSEvent)"))
        XCTAssertTrue(source.contains("performDrag(with: event)"))
        XCTAssertTrue(source.contains("dragHandleHeight: CGFloat = 42"))

        let viewSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/FloatingWidgetView.swift"), encoding: .utf8)
        XCTAssertTrue(viewSource.contains("FloatingWidgetDragHandle: NSViewRepresentable"))
        XCTAssertTrue(viewSource.contains("FloatingWidgetDragHandleView: NSView"))
        XCTAssertTrue(viewSource.contains(".frame(width: FloatingWidgetConstants.width, height: FloatingWidgetConstants.dragHandleHeight)"))
        XCTAssertTrue(viewSource.contains("view.wantsLayer = true"))
        XCTAssertTrue(viewSource.contains("override func acceptsFirstMouse"))
        XCTAssertTrue(viewSource.contains("override func hitTest"))
        XCTAssertTrue(viewSource.contains("window.setFrameOrigin"))
    }

    func testFloatingWidgetWindowHasFixedNonResizableSize() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Controllers/FloatingWidgetController.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("static let size = NSSize(width: 260, height: 260)"))
        XCTAssertTrue(source.contains("newWindow.minSize = FloatingWidgetLayout.size"))
        XCTAssertTrue(source.contains("newWindow.maxSize = FloatingWidgetLayout.size"))
        XCTAssertTrue(source.contains("newWindow.contentMinSize = FloatingWidgetLayout.size"))
        XCTAssertTrue(source.contains("newWindow.contentMaxSize = FloatingWidgetLayout.size"))
        XCTAssertTrue(source.contains("newWindow.setContentSize(FloatingWidgetLayout.size)"))
        XCTAssertTrue(source.contains("newWindow.styleMask.remove(.resizable)"))
    }

    func testFloatingWidgetRowsOpenEventDetails() throws {
        let viewSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/FloatingWidgetView.swift"), encoding: .utf8)
        let controllerSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Controllers/FloatingWidgetController.swift"), encoding: .utf8)
        let coordinatorSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Controllers/WidgetCoordinator.swift"), encoding: .utf8)
        let occurrenceSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendarCore/Services/RecurrenceExpander.swift"), encoding: .utf8)

        XCTAssertTrue(viewSource.contains("let onSelect: (EventOccurrence) -> Void"))
        XCTAssertTrue(viewSource.contains("static let visibleOccurrenceLimit = 3"))
        XCTAssertTrue(viewSource.contains("let visibleOccurrences = Array(occurrences.prefix(FloatingWidgetConstants.visibleOccurrenceLimit))"))
        XCTAssertTrue(viewSource.contains("ForEach(visibleOccurrences, id: \\.occurrenceID)"))
        XCTAssertTrue(viewSource.contains("Text(\"+\\(overflowCount)개\")"))
        XCTAssertTrue(viewSource.contains("Button { onSelect(occurrence) }"))
        XCTAssertTrue(viewSource.contains(".frame(width: FloatingWidgetConstants.width, height: FloatingWidgetConstants.height, alignment: .topLeading)"))
        XCTAssertTrue(viewSource.contains(".truncationMode(.tail)"))
        XCTAssertTrue(controllerSource.contains("private var detailWindow: NSWindow?"))
        XCTAssertTrue(controllerSource.contains("showDetail(for event: CalendarEvent)"))
        XCTAssertTrue(coordinatorSource.contains("onSelect: { [weak self] occurrence in"))
        XCTAssertTrue(coordinatorSource.contains("currentEvents.first(where: { $0.id == occurrence.eventID })"))
        XCTAssertTrue(occurrenceSource.contains("var occurrenceID: String"))
    }

    func testFloatingWidgetKeepsTodayStateFreshAndRestoresOntoVisibleScreen() throws {
        let viewSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/FloatingWidgetView.swift"), encoding: .utf8)
        let controllerSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Controllers/FloatingWidgetController.swift"), encoding: .utf8)

        XCTAssertTrue(viewSource.contains("@State private var now = Date()"))
        XCTAssertTrue(viewSource.contains("Timer.publish(every: 60"))
        XCTAssertTrue(viewSource.contains("Calendar.current.isDate(occurrence.startDate, inSameDayAs: now)"))
        XCTAssertTrue(controllerSource.contains("validatedFrame"))
        XCTAssertTrue(controllerSource.contains("NSScreen.screens"))
        XCTAssertTrue(controllerSource.contains("visibleFrame"))
        XCTAssertTrue(controllerSource.contains("intersects(frame)"))
    }

    func testFloatingWidgetRefreshDoesNotStealKeyboardFocusFromMainWindow() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Controllers/FloatingWidgetController.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("showWithoutActivating()"))
        XCTAssertFalse(source.contains("window?.makeKeyAndOrderFront(nil)"))
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
