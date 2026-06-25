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
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        var configured = calendar
        configured.firstWeekday = 1
        self.calendar = configured
    }

    public func makeMonthGrid(year: Int, month: Int, today: Date = Date()) throws -> [CalendarDayCell] {
        guard (1...12).contains(month) else { throw CalendarGridError.invalidMonth }
        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            throw CalendarGridError.invalidMonth
        }

        let weekday = calendar.component(.weekday, from: monthStart)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let firstCellDate = calendar.date(byAdding: .day, value: -offset, to: monthStart) ?? monthStart

        return (0..<42).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: firstCellDate) else { return nil }
            let day = calendar.component(.day, from: date)
            let isInDisplayedMonth = calendar.component(.year, from: date) == year && calendar.component(.month, from: date) == month
            let weekday = calendar.component(.weekday, from: date)
            return CalendarDayCell(
                date: calendar.startOfDay(for: date),
                day: day,
                isInDisplayedMonth: isInDisplayedMonth,
                isToday: calendar.isDate(date, inSameDayAs: today),
                isSunday: weekday == 1,
                isSaturday: weekday == 7
            )
        }
    }
}
