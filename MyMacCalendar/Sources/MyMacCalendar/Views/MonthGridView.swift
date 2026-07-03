import SwiftUI
import MyMacCalendarCore

enum CalendarDensityMode: String {
    case comfortable
    case compact
}

struct MonthGridView: View {
    let displayedMonth: Date
    @Binding var selectedDate: Date
    let events: [CalendarEvent]
    let holidays: [HolidayRecord]
    let density: CalendarDensityMode
    let onCreateEvent: (Date) -> Void
    let onSelectEvent: (CalendarEvent) -> Void
    @State private var overflowDate: Date?

    private let calendar = Calendar.current
    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private enum CalendarGridLayout {
        static func visibleEntryLimit(for density: CalendarDensityMode) -> Int {
            density == .compact ? 3 : 2
        }

        static func entryHeight(for density: CalendarDensityMode) -> CGFloat {
            density == .compact ? 14 : 16
        }

        static func entrySpacing(for density: CalendarDensityMode) -> CGFloat {
            density == .compact ? 1 : 2
        }

        static let dateTopPadding: CGFloat = 2
        static func dateHorizontalPadding(for density: CalendarDensityMode) -> CGFloat {
            density == .compact ? 10 : 14
        }

        static func entryTopPadding(for density: CalendarDensityMode) -> CGFloat {
            density == .compact ? 2 : 4
        }

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
            let preparedData = makePreparedData()

            VStack(spacing: 0) {
                weekdayHeader(height: headerHeight)
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(preparedData.cells, id: \.date) { cell in
                        dayCell(cell, height: cellHeight, preparedData: preparedData)
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

    private func dayCell(_ cell: CalendarDayCell, height: CGFloat, preparedData: MonthGridPreparedData) -> some View {
        let dayEntries = preparedData.entriesByDay[dayKey(for: cell.date)] ?? []
        let visibleEntries = Array(dayEntries.prefix(CalendarGridLayout.visibleEntryLimit(for: density)))
        let overflowCount = max(0, dayEntries.count - visibleEntries.count)

        return ZStack(alignment: .topLeading) {
            cellBackground(for: cell)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Spacer(minLength: 0)
                    dateLabel(for: cell, preparedData: preparedData)
                }
                .padding(.top, CalendarGridLayout.dateTopPadding)
                .padding(.horizontal, CalendarGridLayout.dateHorizontalPadding(for: density))

                VStack(alignment: .leading, spacing: CalendarGridLayout.entrySpacing(for: density)) {
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
                                .frame(height: CalendarGridLayout.entryHeight(for: density))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: overflowPopoverBinding(for: cell.date)) {
                            DayOverflowPopover(
                                date: cell.date,
                                entries: dayEntries,
                                eventsByID: preparedData.eventsByID,
                                onSelectEvent: onSelectEvent
                            )
                        }
                        .help("이 날짜의 모든 항목 보기")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, CalendarGridLayout.entryTopPadding(for: density))

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

    private func dateLabel(for cell: CalendarDayCell, preparedData: MonthGridPreparedData) -> some View {
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
                    .foregroundStyle(textColor(for: cell, preparedData: preparedData))
            } else {
                Text(dayText(for: cell))
                    .font(.system(size: CalendarGridTypography.dateFontSize, weight: .semibold))
                    .foregroundStyle(textColor(for: cell, preparedData: preparedData))
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
            .frame(
                maxWidth: .infinity,
                minHeight: CalendarGridLayout.entryHeight(for: density),
                maxHeight: CalendarGridLayout.entryHeight(for: density)
            )
            .background(entry.background)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(entry.kind == .holiday)
        .help(entry.title)
    }

    private var cells: [CalendarDayCell] {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let year = components.year,
              let month = components.month else {
            return []
        }
        return (try? CalendarGridBuilder().makeMonthGrid(year: year, month: month)) ?? []
    }

    private func makePreparedData() -> MonthGridPreparedData {
        let monthCells = cells
        guard let firstDate = monthCells.first?.date,
              let lastDate = monthCells.last?.date,
              let endDate = calendar.date(byAdding: .day, value: 1, to: lastDate) else {
            return MonthGridPreparedData(cells: monthCells, entriesByDay: [:], holidaysByDay: [:], eventsByID: [:])
        }

        let dayKeys = Set(monthCells.map { dayKey(for: $0.date) })
        let holidaysByDay = makeHolidaysByDay()
        let interval = DateInterval(start: firstDate, end: endDate)
        let expander = RecurrenceExpander(calendar: calendar)
        let visibleOccurrences = events.flatMap { expander.occurrences(for: $0, in: interval) }
        var eventEntriesByDay: [Date: [CalendarEntry]] = [:]

        for occurrence in visibleOccurrences {
            var currentDay = dayKey(for: occurrence.startDate)
            let finalDay = dayKey(for: occurrence.endDate)
            while currentDay <= finalDay {
                if dayKeys.contains(currentDay) {
                    eventEntriesByDay[currentDay, default: []].append(
                        CalendarEntry(
                            id: "event-\(occurrence.eventID.uuidString)-\(occurrence.startDate.timeIntervalSinceReferenceDate)-\(currentDay.timeIntervalSinceReferenceDate)",
                            title: occurrence.title,
                            kind: .event,
                            colorHex: occurrence.colorHex,
                            eventID: occurrence.eventID,
                            sortDate: occurrence.startDate
                        )
                    )
                }

                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else {
                    break
                }
                currentDay = nextDay
            }
        }

        var entriesByDay: [Date: [CalendarEntry]] = [:]
        for cell in monthCells {
            let key = dayKey(for: cell.date)
            let holidayEntries = (holidaysByDay[key] ?? []).map { holiday in
                CalendarEntry(
                    id: "holiday-\(holiday.id.uuidString)",
                    title: holiday.title,
                    kind: .holiday,
                    colorHex: nil,
                    eventID: nil,
                    sortDate: holiday.date
                )
            }
            let eventEntries = (eventEntriesByDay[key] ?? []).sorted {
                if $0.sortDate == $1.sortDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.sortDate < $1.sortDate
            }
            entriesByDay[key] = holidayEntries + eventEntries
        }

        return MonthGridPreparedData(
            cells: monthCells,
            entriesByDay: entriesByDay,
            holidaysByDay: holidaysByDay,
            eventsByID: Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        )
    }

    private func makeHolidaysByDay() -> [Date: [HolidayRecord]] {
        var grouped: [Date: [HolidayRecord]] = [:]
        for holiday in holidays where holiday.isHidden == false {
            grouped[dayKey(for: holiday.date), default: []].append(holiday)
        }
        return grouped.mapValues { records in
            let manual = records.filter { $0.source == .manual }
            return manual.isEmpty ? records : manual
        }
    }

    private func dayKey(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func dayText(for cell: CalendarDayCell) -> String {
        if cell.day == 1 {
            let month = calendar.component(.month, from: cell.date)
            return "\(month)월 \(cell.day)일"
        }
        return "\(cell.day)일"
    }

    private func textColor(for cell: CalendarDayCell, preparedData: MonthGridPreparedData) -> Color {
        if cell.isInDisplayedMonth == false {
            return AppTheme.mutedText
        }
        if (preparedData.holidaysByDay[dayKey(for: cell.date)]?.isEmpty == false) || cell.isSunday {
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
    let eventsByID: [UUID: CalendarEvent]
    let onSelectEvent: (CalendarEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(dateTitle)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    if let eventID = entry.eventID,
                       let event = eventsByID[eventID] {
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
    let sortDate: Date

    var background: Color {
        switch kind {
        case .holiday:
            return AppTheme.holidayPurple
        case .event:
            return Color(hex: colorHex ?? "#4F7DFF").opacity(0.82)
        }
    }
}

private struct MonthGridPreparedData {
    let cells: [CalendarDayCell]
    let entriesByDay: [Date: [CalendarEntry]]
    let holidaysByDay: [Date: [HolidayRecord]]
    let eventsByID: [UUID: CalendarEvent]
}
