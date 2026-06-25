import SwiftUI
import SwiftData
import MyMacCalendarCore

struct MainWindowView: View {
    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]
    @Query(sort: \HolidayRecord.date) private var holidays: [HolidayRecord]
    @Query private var settingsRows: [AppSettings]
    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                header
                MonthGridView(displayedMonth: displayedMonth, selectedDate: $selectedDate, events: filteredEvents, holidays: holidays)
            }
            .padding(20)
            .frame(minWidth: 720)
        } detail: {
            AgendaPanelView(
                selectedDate: selectedDate,
                events: filteredEvents,
                onSelectEvent: { event in
                    activeSheet = .editEvent(event)
                },
                onSelectOccurrence: { occurrence in
                    selectedDate = occurrence.startDate
                    if let event = events.first(where: { $0.id == occurrence.eventID }) {
                        activeSheet = .editEvent(event)
                    }
                }
            )
                .frame(minWidth: 320)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Today") {
                    displayedMonth = Date()
                    selectedDate = Date()
                }
                Button {
                    activeSheet = .quickAdd
                } label: {
                    Label("Quick Add", systemImage: "bolt")
                }
                Button {
                    activeSheet = .newEvent(selectedDate)
                } label: {
                    Label("New Event", systemImage: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newEvent(let defaultDate):
                EventEditorView(defaultDate: defaultDate)
            case .quickAdd:
                QuickAddView()
            case .editEvent(let event):
                EventEditorView(event: event)
            }
        }
        .task(id: widgetRefreshToken) {
            WidgetCoordinator.shared.update(events: events, settings: settingsRows.first)
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

    private var widgetRefreshToken: String {
        let settingsToken: String
        if let settings = settingsRows.first {
            settingsToken = [
                settings.floatingWidgetEnabled.description,
                settings.floatingWidgetAlwaysOnTop.description,
                String(settings.floatingWidgetOpacity),
                String(settings.floatingWidgetVisibleCount)
            ].joined(separator: "|")
        } else {
            settingsToken = "default"
        }

        let eventsToken = events
            .map { event in
                [
                    event.id.uuidString,
                    String(event.updatedAt.timeIntervalSinceReferenceDate),
                    String(event.startDate.timeIntervalSinceReferenceDate),
                    String(event.endDate.timeIntervalSinceReferenceDate)
                ].joined(separator: "|")
            }
            .joined(separator: ";")

        return settingsToken + "::" + eventsToken
    }
}

private enum ActiveSheet: Identifiable {
    case newEvent(Date)
    case quickAdd
    case editEvent(CalendarEvent)

    var id: String {
        switch self {
        case .newEvent(let date):
            return "new-\(date.timeIntervalSinceReferenceDate)"
        case .quickAdd:
            return "quick-add"
        case .editEvent(let event):
            return "edit-\(event.id.uuidString)"
        }
    }
}
