import Foundation

public enum AllDayDate {
    /// Reconstruct the original civil day in the viewer's zone, rather than
    /// converting a midnight instant into a different calendar day.
    public static func resolve(_ date: Date, storedTimeZone: String, calendar: Calendar = .current) -> Date {
        guard let zone = TimeZone(identifier: storedTimeZone) else { return date }
        var source = Calendar(identifier: .gregorian)
        source.timeZone = zone
        var destination = Calendar(identifier: .gregorian)
        destination.timeZone = calendar.timeZone
        return destination.date(from: source.dateComponents([.year, .month, .day], from: date)) ?? date
    }
}
