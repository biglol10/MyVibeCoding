import Foundation

public struct QuickAddResult: Equatable {
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let needsConfirmation: Bool
}

public struct QuickAddParser {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func parse(_ input: String, now: Date = Date()) -> QuickAddResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = parseISO(trimmed) ?? parseSlash(trimmed, now: now) ?? parseNextWeekday(trimmed, now: now) {
            return parsed
        }

        let fallback = calendar.startOfDay(for: now)
        return QuickAddResult(title: trimmed, startDate: fallback, endDate: fallback, needsConfirmation: true)
    }

    private func parseISO(_ input: String) -> QuickAddResult? {
        let pattern = #"^(\d{4})-(\d{1,2})-(\d{1,2})\s+(.+)$"#
        guard let match = input.firstMatch(pattern: pattern) else { return nil }
        guard let year = Int(match[1]), let month = Int(match[2]), let day = Int(match[3]) else { return nil }
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let normalized = calendar.startOfDay(for: date)
        return QuickAddResult(title: match[4], startDate: normalized, endDate: normalized, needsConfirmation: false)
    }

    private func parseSlash(_ input: String, now: Date) -> QuickAddResult? {
        let pattern = #"^(\d{1,2})/(\d{1,2})\s+(.+)$"#
        guard let match = input.firstMatch(pattern: pattern) else { return nil }
        guard let month = Int(match[1]), let day = Int(match[2]) else { return nil }
        let year = calendar.component(.year, from: now)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let normalized = calendar.startOfDay(for: date)
        return QuickAddResult(title: match[3], startDate: normalized, endDate: normalized, needsConfirmation: false)
    }

    private func parseNextWeekday(_ input: String, now: Date) -> QuickAddResult? {
        let weekdays = [
            "일요일": 1,
            "월요일": 2,
            "화요일": 3,
            "수요일": 4,
            "목요일": 5,
            "금요일": 6,
            "토요일": 7
        ]

        for (word, weekday) in weekdays {
            let prefix = "다음주 \(word) "
            guard input.hasPrefix(prefix) else { continue }
            let title = String(input.dropFirst(prefix.count))
            let startOfToday = calendar.startOfDay(for: now)
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: startOfToday) else { return nil }
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: nextWeek)
            components.weekday = weekday
            guard let date = calendar.date(from: components) else { return nil }
            let normalized = calendar.startOfDay(for: date)
            return QuickAddResult(title: title, startDate: normalized, endDate: normalized, needsConfirmation: false)
        }

        return nil
    }
}

private extension String {
    func firstMatch(pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: nsRange) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: self) else { return nil }
            return String(self[range])
        }
    }
}
