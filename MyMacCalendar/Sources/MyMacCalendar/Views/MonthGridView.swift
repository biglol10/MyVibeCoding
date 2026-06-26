import SwiftUI
import MyMacCalendarCore

struct MonthGridView: View {
    let displayedMonth: Date
    @Binding var selectedDate: Date
    let events: [CalendarEvent]
    let holidays: [HolidayRecord]
    let onCreateEvent: (Date) -> Void
    let onSelectEvent: (CalendarEvent) -> Void
    @State private var overflowDate: Date?

    private let calendar = Calendar.current
    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private enum CalendarGridLayout {
        static let visibleEntryLimit = 2
        static let entryHeight: CGFloat = 16
        static let entrySpacing: CGFloat = 2
        static let dateTopPadding: CGFloat = 2
        static let dateHorizontalPadding: CGFloat = 14
        static let entryTopPadding: CGFloat = 4
        static let bottomPadding: CGFloat = 4
    }
    private enum CalendarGridTypography {
        static let weekdayFontSize: CGFloat = 14
        static let dateFontSize: CGFloat = 15
        static let todayFontSize: CGFloat = 15
        static let todayBadgeSize: CGFloat = 24
        static let entryFontSize: CGFloat = 11
        static let overflowFontSize: CGFloat = 10
    }

    var body: some View {
        GeometryReader { proxy in
            let headerHeight: CGFloat = 54
            let cellHeight = max(92, (proxy.size.height - headerHeight) / 6)

            VStack(spacing: 0) {
                weekdayHeader(height: headerHeight)
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(cells, id: \.date) { cell in
                        dayCell(cell, height: cellHeight)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(AppTheme.windowBackground)
    }

    private func weekdayHeader(height: CGFloat) -> some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.system(size: CalendarGridTypography.weekdayFontSize, weight: .bold))
                    .foregroundStyle(weekdayColor(for: index).opacity(index == 0 || index == 6 ? 0.9 : 0.78))
                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(AppTheme.gridLine)
                            .frame(height: 1)
                    }
            }
        }
    }

    private func dayCell(_ cell: CalendarDayCell, height: CGFloat) -> some View {
        let dayEntries = entries(for: cell.date)
        let visibleEntries = Array(dayEntries.prefix(CalendarGridLayout.visibleEntryLimit))
        let overflowCount = max(0, dayEntries.count - visibleEntries.count)

        return ZStack(alignment: .topLeading) {
            cellBackground(for: cell)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Spacer(minLength: 0)
                    dateLabel(for: cell)
                }
                .padding(.top, CalendarGridLayout.dateTopPadding)
                .padding(.horizontal, CalendarGridLayout.dateHorizontalPadding)

                VStack(alignment: .leading, spacing: CalendarGridLayout.entrySpacing) {
                    ForEach(visibleEntries) { entry in
                        entryPill(entry)
                    }

                    if overflowCount > 0 {
                        Button {
                            selectedDate = cell.date
                            overflowDate = cell.date
                        } label: {
                            Text("+\(overflowCount)개")
                                .font(.system(size: CalendarGridTypography.overflowFontSize, weight: .bold))
                                .foregroundStyle(AppTheme.secondaryText)
                                .padding(.horizontal, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: CalendarGridLayout.entryHeight)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: overflowPopoverBinding(for: cell.date)) {
                            DayOverflowPopover(
                                date: cell.date,
                                entries: dayEntries,
                                events: events,
                                onSelectEvent: onSelectEvent
                            )
                        }
                        .help("이 날짜의 모든 항목 보기")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, CalendarGridLayout.entryTopPadding)

                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .clipShape(Rectangle())
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDate = cell.date
        }
        .onTapGesture(count: 2) {
            selectedDate = cell.date
            onCreateEvent(cell.date)
        }
        .overlay {
            let isSelected = calendar.isDate(cell.date, inSameDayAs: selectedDate)
            Rectangle()
                .strokeBorder(isSelected ? AppTheme.selectedCellBorder : AppTheme.gridLine, lineWidth: isSelected ? 1.8 : 0.8)
        }
        .opacity(cell.isInDisplayedMonth ? 1 : 0.48)
    }

    private func cellBackground(for cell: CalendarDayCell) -> some View {
        let isSelected = calendar.isDate(cell.date, inSameDayAs: selectedDate)

        return ZStack {
            if cell.isInDisplayedMonth {
                (cell.isSaturday || cell.isSunday ? AppTheme.alternateCellBackground : AppTheme.cellBackground)
            } else {
                AppTheme.windowBackground
            }

            if isSelected {
                AppTheme.selectedCellBackground
            }
        }
    }

    private func dateLabel(for cell: CalendarDayCell) -> some View {
        HStack(alignment: .center, spacing: 4) {
            if cell.isToday {
                Text("\(cell.day)")
                    .font(.system(size: CalendarGridTypography.todayFontSize, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: CalendarGridTypography.todayBadgeSize, height: CalendarGridTypography.todayBadgeSize)
                    .background(AppTheme.todayRed)
                    .clipShape(Circle())

                Text("일")
                    .font(.system(size: CalendarGridTypography.dateFontSize, weight: .semibold))
                    .foregroundStyle(textColor(for: cell))
            } else {
                Text(dayText(for: cell))
                    .font(.system(size: CalendarGridTypography.dateFontSize, weight: .semibold))
                    .foregroundStyle(textColor(for: cell))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func entryPill(_ entry: CalendarEntry) -> some View {
        Button {
            if let eventID = entry.eventID, let event = events.first(where: { $0.id == eventID }) {
                onSelectEvent(event)
            }
        } label: {
            HStack(spacing: 5) {
                if entry.kind == .holiday {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.65))
                        .frame(width: 17, height: 17)
                        .background(AppTheme.holidayText)
                        .clipShape(Circle())
                }

                Text(entry.title)
                    .font(.system(size: CalendarGridTypography.entryFontSize, weight: .bold))
                    .foregroundStyle(entry.kind == .holiday ? AppTheme.holidayText : Color.white.opacity(0.94))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.leading, entry.kind == .holiday ? 3 : 9)
            .padding(.trailing, 9)
            .frame(maxWidth: .infinity, minHeight: CalendarGridLayout.entryHeight, maxHeight: CalendarGridLayout.entryHeight)
            .background(entry.background)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(entry.kind == .holiday)
        .help(entry.title)
    }

    private var cells: [CalendarDayCell] {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        return (try? CalendarGridBuilder().makeMonthGrid(year: components.year ?? 2026, month: components.month ?? 1)) ?? []
    }

    private var visibleOccurrences: [EventOccurrence] {
        guard let firstDate = cells.first?.date,
              let lastDate = cells.last?.date,
              let endDate = calendar.date(byAdding: .day, value: 1, to: lastDate) else {
            return []
        }

        let interval = DateInterval(start: firstDate, end: endDate)
        let expander = RecurrenceExpander(calendar: calendar)
        return events.flatMap { expander.occurrences(for: $0, in: interval) }
    }

    private func entries(for date: Date) -> [CalendarEntry] {
        let holidayEntries = holidaysForDate(date).map { holiday in
            CalendarEntry(
                id: "holiday-\(holiday.id.uuidString)",
                title: holiday.title,
                kind: .holiday,
                colorHex: nil,
                eventID: nil
            )
        }

        let eventEntries = visibleOccurrences
            .filter { occurrence in
                let start = calendar.startOfDay(for: occurrence.startDate)
                let end = calendar.startOfDay(for: occurrence.endDate)
                return start <= date && date <= end
            }
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.startDate < $1.startDate
            }
            .map { occurrence in
                CalendarEntry(
                    id: "event-\(occurrence.eventID.uuidString)-\(occurrence.startDate.timeIntervalSinceReferenceDate)",
                    title: occurrence.title,
                    kind: .event,
                    colorHex: occurrence.colorHex,
                    eventID: occurrence.eventID
                )
            }

        return holidayEntries + eventEntries
    }

    private func holidaysForDate(_ date: Date) -> [HolidayRecord] {
        let visible = holidays.filter { holiday in
            holiday.isHidden == false && calendar.isDate(holiday.date, inSameDayAs: date)
        }
        let manual = visible.filter { $0.source == .manual }
        return manual.isEmpty ? visible : manual
    }

    private func dayText(for cell: CalendarDayCell) -> String {
        if cell.day == 1 {
            let month = calendar.component(.month, from: cell.date)
            return "\(month)월 \(cell.day)일"
        }
        return "\(cell.day)일"
    }

    private func textColor(for cell: CalendarDayCell) -> Color {
        if cell.isInDisplayedMonth == false {
            return AppTheme.mutedText
        }
        if holidaysForDate(cell.date).isEmpty == false || cell.isSunday {
            return AppTheme.sundayText.opacity(0.82)
        }
        if cell.isSaturday {
            return AppTheme.secondaryText
        }
        return AppTheme.primaryText
    }

    private func weekdayColor(for index: Int) -> Color {
        if index == 0 {
            return AppTheme.sundayText
        }
        if index == 6 {
            return AppTheme.secondaryText
        }
        return AppTheme.primaryText
    }

    private func overflowPopoverBinding(for date: Date) -> Binding<Bool> {
        Binding(
            get: {
                guard let overflowDate else { return false }
                return calendar.isDate(overflowDate, inSameDayAs: date)
            },
            set: { isPresented in
                if isPresented == false {
                    overflowDate = nil
                }
            }
        )
    }
}

private struct DayOverflowPopover: View {
    let date: Date
    let entries: [CalendarEntry]
    let events: [CalendarEvent]
    let onSelectEvent: (CalendarEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(dateTitle)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    if let eventID = entry.eventID,
                       let event = events.first(where: { $0.id == eventID }) {
                        Button {
                            onSelectEvent(event)
                        } label: {
                            overflowRow(entry)
                        }
                        .buttonStyle(.plain)
                    } else {
                        overflowRow(entry)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .topLeading)
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: date)
    }

    private func overflowRow(_ entry: CalendarEntry) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.background)
                .frame(width: 4, height: 24)
            Text(entry.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct CalendarEntry: Identifiable {
    enum Kind {
        case holiday
        case event
    }

    let id: String
    let title: String
    let kind: Kind
    let colorHex: String?
    let eventID: UUID?

    var background: Color {
        switch kind {
        case .holiday:
            return AppTheme.holidayPurple
        case .event:
            return Color(hex: colorHex ?? "#4F7DFF").opacity(0.82)
        }
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
