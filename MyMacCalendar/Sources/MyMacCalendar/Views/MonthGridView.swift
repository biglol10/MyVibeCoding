import SwiftUI
import MyMacCalendarCore

struct MonthGridView: View {
    let displayedMonth: Date
    @Binding var selectedDate: Date
    let events: [CalendarEvent]
    let holidays: [HolidayRecord]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(symbol == "Sun" ? .red : symbol == "Sat" ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(cells, id: \.date) { cell in
                    Button {
                        selectedDate = cell.date
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(cell.day)")
                                .font(.system(size: 15, weight: Calendar.current.isDate(cell.date, inSameDayAs: selectedDate) ? .bold : .medium))
                                .foregroundStyle(textColor(for: cell))
                            Spacer()
                            HStack(spacing: 3) {
                                ForEach(markers(for: cell.date).prefix(3), id: \.self) { color in
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 5, height: 5)
                                }
                            }
                        }
                        .padding(8)
                        .frame(minHeight: 86, alignment: .topLeading)
                        .background(Calendar.current.isDate(cell.date, inSameDayAs: selectedDate) ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(cell.isInDisplayedMonth ? 1 : 0.38)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var cells: [CalendarDayCell] {
        let components = Calendar.current.dateComponents([.year, .month], from: displayedMonth)
        return (try? CalendarGridBuilder().makeMonthGrid(year: components.year ?? 2026, month: components.month ?? 1)) ?? []
    }

    private func markers(for date: Date) -> [String] {
        events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) }.map(\.colorHex)
    }

    private func textColor(for cell: CalendarDayCell) -> Color {
        if holidays.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: cell.date) && $0.isHidden == false }) || cell.isSunday {
            return .red
        }
        if cell.isSaturday {
            return .blue
        }
        return .primary
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
