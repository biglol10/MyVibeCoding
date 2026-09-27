import Foundation

public enum CalendarNavigation {
    public static func movingMonth(from displayedMonth: Date, selectedDate: Date, by offset: Int, calendar: Calendar = .current) -> Date {
        guard let monthStart = calendar.dateInterval(of: .month, for: displayedMonth)?.start,
              let target = calendar.date(byAdding: .month, value: offset, to: monthStart),
              let days = calendar.range(of: .day, in: .month, for: target) else { return selectedDate }
        let day = min(calendar.component(.day, from: selectedDate), days.count)
        return calendar.date(byAdding: .day, value: day - 1, to: target) ?? target
    }
}
