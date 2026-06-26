import SwiftUI
import MyMacCalendarCore

struct DayAgendaPanelView: View {
    let selectedDate: Date
    let events: [CalendarEvent]
    let holidays: [HolidayRecord]
    let onCreateEvent: (Date) -> Void
    let onSelectEvent: (CalendarEvent) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    holidaySection
                    eventSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
        .background(Color(red: 0.10, green: 0.095, blue: 0.095))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(dateTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text("\(dayEvents.count)개 일정")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Button {
                    onCreateEvent(selectedDate)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .help("선택한 날짜에 일정 추가")
            }
        }
        .padding(18)
        .background(AppTheme.headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.gridLine)
                .frame(height: 1)
        }
    }

    private var holidaySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("휴일")
            if dayHolidays.isEmpty {
                emptyText("등록된 휴일 없음")
            } else {
                ForEach(dayHolidays, id: \.id) { holiday in
                    HStack(spacing: 9) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.65))
                            .frame(width: 20, height: 20)
                            .background(AppTheme.holidayText)
                            .clipShape(Circle())
                        Text(holiday.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.holidayText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var eventSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("일정")
            if dayEvents.isEmpty {
                emptyText("등록된 일정 없음")
            } else {
                ForEach(dayEvents, id: \.occurrenceID) { item in
                    Button {
                        let event = item.event
                        onSelectEvent(event)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: item.event.colorHex))
                                .frame(width: 4, height: 34)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.occurrence.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(AppTheme.primaryText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(item.event.category.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("일정 편집")
                }
            }
        }
    }

    private var dayEvents: [DayAgendaItem] {
        let start = calendar.startOfDay(for: selectedDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let interval = DateInterval(start: start, end: end)
        let expander = RecurrenceExpander(calendar: calendar)

        return events
            .flatMap { event in
                expander.occurrences(for: event, in: interval)
                    .filter { occurrence in
                        calendar.startOfDay(for: occurrence.startDate) <= start &&
                            start <= calendar.startOfDay(for: occurrence.endDate)
                    }
                    .map { DayAgendaItem(event: event, occurrence: $0) }
            }
            .sorted {
                if $0.occurrence.startDate == $1.occurrence.startDate {
                    return $0.occurrence.title.localizedCaseInsensitiveCompare($1.occurrence.title) == .orderedAscending
                }
                return $0.occurrence.startDate < $1.occurrence.startDate
            }
    }

    private var dayHolidays: [HolidayRecord] {
        let visible = holidays.filter { holiday in
            holiday.isHidden == false && calendar.isDate(holiday.date, inSameDayAs: selectedDate)
        }
        let manual = visible.filter { $0.source == .manual }
        return manual.isEmpty ? visible : manual
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 (E)"
        return formatter.string(from: selectedDate)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(AppTheme.secondaryText)
    }

    private func emptyText(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

private struct DayAgendaItem {
    let event: CalendarEvent
    let occurrence: EventOccurrence

    var occurrenceID: String {
        "\(event.id.uuidString)-\(occurrence.startDate.timeIntervalSinceReferenceDate)"
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
