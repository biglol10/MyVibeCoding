import AppKit
import SwiftUI
import SwiftData
import MyMacCalendarCore

struct MainWindowView: View {
    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]
    @Query(sort: \HolidayRecord.date) private var holidays: [HolidayRecord]
    @Query private var settingsRows: [AppSettings]
    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    @State private var activeSheet: ActiveSheet?
    private enum MainWindowTypography {
        static let monthTitleFontSize: CGFloat = 38
        static let toolbarIconSize: CGFloat = 15
        static let toolbarTextFontSize: CGFloat = 14
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                MonthGridView(
                    displayedMonth: displayedMonth,
                    selectedDate: $selectedDate,
                    events: events,
                    holidays: holidays,
                    onCreateEvent: { date in
                        selectedDate = date
                        activeSheet = .newEvent(date)
                    },
                    onSelectEvent: { event in
                        activeSheet = .editEvent(event)
                    }
                )

                Rectangle()
                    .fill(AppTheme.gridLine)
                    .frame(width: 1)

                DayAgendaPanelView(
                    selectedDate: selectedDate,
                    events: events,
                    holidays: holidays,
                    onCreateEvent: { date in
                        selectedDate = date
                        activeSheet = .newEvent(date)
                    },
                    onSelectEvent: { event in
                        activeSheet = .editEvent(event)
                    }
                )
                .frame(width: 280)
            }
        }
        .frame(minWidth: 1240, minHeight: 680)
        .background(AppTheme.windowBackground)
        .background(MainWindowCloseAccessor())
        .preferredColorScheme(.dark)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newEvent(let defaultDate):
                EventEditorView(defaultDate: defaultDate)
            case .quickAdd:
                QuickAddView()
            case .editEvent(let event):
                EventEditorView(event: event)
            case .settings:
                SettingsView()
            }
        }
        .task(id: widgetRefreshToken) {
            WidgetCoordinator.shared.update(events: events, settings: settingsRows.first)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openQuickAddSheet)) { _ in
            activeSheet = .quickAdd
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsSheet)) { _ in
            activeSheet = .settings
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(monthTitle)
                .font(.system(size: MainWindowTypography.monthTitleFontSize, weight: .bold, design: .default))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 24)

            Button {
                displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(CalendarToolbarButtonStyle(size: MainWindowTypography.toolbarIconSize))
            .help("Previous month")

            Button("오늘") {
                displayedMonth = Date()
                selectedDate = Date()
            }
            .buttonStyle(CalendarTextToolbarButtonStyle(size: MainWindowTypography.toolbarTextFontSize))
            .help("Today")

            Button {
                displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(CalendarToolbarButtonStyle(size: MainWindowTypography.toolbarIconSize))
            .help("Next month")

            Divider()
                .frame(height: 24)
                .overlay(AppTheme.gridLine)

            Button {
                activeSheet = .quickAdd
            } label: {
                Image(systemName: "bolt.fill")
            }
            .buttonStyle(CalendarToolbarButtonStyle(size: MainWindowTypography.toolbarIconSize))
            .help("Quick add")

            Button {
                activeSheet = .newEvent(selectedDate)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(CalendarToolbarButtonStyle(size: MainWindowTypography.toolbarIconSize))
            .help("New event")

            Button {
                activeSheet = .settings
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(CalendarToolbarButtonStyle(size: MainWindowTypography.toolbarIconSize))
            .help("Settings")
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(AppTheme.headerBackground)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: displayedMonth)
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

private struct MainWindowCloseAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.delegate = MainWindowCloseDelegate.shared
    }
}

@MainActor
private final class MainWindowCloseDelegate: NSObject, NSWindowDelegate {
    static let shared = MainWindowCloseDelegate()

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

enum AppTheme {
    static let windowBackground = Color(red: 0.12, green: 0.11, blue: 0.11)
    static let headerBackground = Color(red: 0.12, green: 0.11, blue: 0.11)
    static let cellBackground = Color(red: 0.13, green: 0.12, blue: 0.12)
    static let alternateCellBackground = Color(red: 0.145, green: 0.14, blue: 0.135)
    static let selectedCellBackground = Color.white.opacity(0.075)
    static let selectedCellBorder = Color.white.opacity(0.34)
    static let gridLine = Color.white.opacity(0.13)
    static let primaryText = Color(red: 0.88, green: 0.88, blue: 0.88)
    static let secondaryText = Color(red: 0.62, green: 0.62, blue: 0.64)
    static let mutedText = Color(red: 0.38, green: 0.38, blue: 0.40)
    static let sundayText = Color(red: 1.0, green: 0.28, blue: 0.25)
    static let saturdayText = Color(red: 0.16, green: 0.54, blue: 1.0)
    static let todayRed = Color(red: 1.0, green: 0.22, blue: 0.20)
    static let holidayPurple = Color(red: 0.39, green: 0.21, blue: 0.46)
    static let holidayText = Color(red: 0.92, green: 0.48, blue: 1.0)
}

private struct CalendarToolbarButtonStyle: ButtonStyle {
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(AppTheme.primaryText)
            .frame(width: 34, height: 32)
            .background(configuration.isPressed ? Color.white.opacity(0.22) : Color.white.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct CalendarTextToolbarButtonStyle: ButtonStyle {
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, 18)
            .frame(height: 32)
            .background(configuration.isPressed ? Color.white.opacity(0.22) : Color.white.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private enum ActiveSheet: Identifiable {
    case newEvent(Date)
    case quickAdd
    case editEvent(CalendarEvent)
    case settings

    var id: String {
        switch self {
        case .newEvent(let date):
            return "new-\(date.timeIntervalSinceReferenceDate)"
        case .quickAdd:
            return "quick-add"
        case .editEvent(let event):
            return "edit-\(event.id.uuidString)"
        case .settings:
            return "settings"
        }
    }
}
