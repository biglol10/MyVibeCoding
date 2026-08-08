import Foundation

public struct HolidayImport: Equatable, Sendable {
    public let date: Date
    public let title: String
    public let providerKey: String

    public init(date: Date, title: String, providerKey: String) {
        self.date = date
        self.title = title
        self.providerKey = providerKey
    }
}

public enum HolidayServiceError: Error, Equatable {
    case invalidURL
    case badStatus(Int)
    case invalidResponse
}

private struct NagerHolidayDTO: Decodable {
    let date: String
    let localName: String
}

public struct NagerHolidayDecoder {
    public init() {}

    public func decode(data: Data, calendar: Calendar = .current) throws -> [HolidayImport] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false

        return try JSONDecoder().decode([NagerHolidayDTO].self, from: data).map { dto in
            guard let date = formatter.date(from: dto.date) else {
                throw HolidayServiceError.invalidResponse
            }
            let normalized = calendar.startOfDay(for: date)
            return HolidayImport(date: normalized, title: dto.localName, providerKey: "\(dto.date)-\(dto.localName)")
        }
    }
}

public struct HolidayMerger {
    public init() {}

    public func merge(imports: [HolidayImport], existing: [HolidayRecord], year: Int) -> [HolidayRecord] {
        let hiddenApiHolidays = existing.filter { $0.source == .api && $0.isHidden && $0.year == year }
        let hiddenKeys = Set(hiddenApiHolidays.map(\.providerKey))
        let hiddenDays = Set(hiddenApiHolidays.map { dayKey($0.date) })
        let manualByDate = Dictionary(grouping: existing.filter { $0.source == .manual && $0.year == year }, by: { dayKey($0.date) })
            .compactMapValues { $0.sorted { $0.updatedAt > $1.updatedAt }.first }

        var merged: [HolidayRecord] = []
        for item in imports where isDate(item.date, inYear: year) && hiddenKeys.contains(item.providerKey) == false && hiddenDays.contains(dayKey(item.date)) == false {
            let key = dayKey(item.date)
            if manualByDate[key] == nil {
                merged.append(HolidayRecord(date: item.date, title: item.title, source: .api, providerKey: item.providerKey, year: year))
            }
        }

        merged.append(contentsOf: manualByDate.values)
        return merged.sorted { $0.date < $1.date }
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func isDate(_ date: Date, inYear year: Int) -> Bool {
        Calendar(identifier: .gregorian).component(.year, from: date) == year
    }
}

public struct HolidayImportPlanner {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func newRecords(imports: [HolidayImport], existing: [HolidayRecord], year: Int) -> [HolidayRecord] {
        let existingAPI = existing.filter { $0.source == .api && $0.year == year }
        let existingProviderKeys = Set(existingAPI.map(\.providerKey))
        let existingDays = Set(existingAPI.map { calendar.startOfDay(for: $0.date) })
        let merged = HolidayMerger().merge(imports: imports, existing: existing, year: year)
        var plannedProviderKeys = Set<String>()
        var plannedDays = Set<Date>()

        return merged.filter { holiday in
            guard holiday.source == .api, holiday.isHidden == false else { return false }
            let day = calendar.startOfDay(for: holiday.date)
            guard existingProviderKeys.contains(holiday.providerKey) == false,
                  existingDays.contains(day) == false,
                  plannedProviderKeys.insert(holiday.providerKey).inserted,
                  plannedDays.insert(day).inserted else {
                return false
            }
            return true
        }
    }
}

public struct HolidayAutoRefreshPolicy {
    public init() {}

    public func shouldFetch(year: Int, existingAPIYears: Set<Int>, attemptedYears: Set<Int>) -> Bool {
        year > 0 && existingAPIYears.contains(year) == false && attemptedYears.contains(year) == false
    }
}

public struct HolidayService {
    private let session: URLSession
    private let decoder: NagerHolidayDecoder

    public init(session: URLSession = .shared, decoder: NagerHolidayDecoder = NagerHolidayDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    public func fetchKoreanHolidays(year: Int) async throws -> [HolidayImport] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "date.nager.at"
        components.path = "/api/v3/PublicHolidays/\(year)/KR"
        guard let url = components.url else {
            throw HolidayServiceError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HolidayServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HolidayServiceError.badStatus(httpResponse.statusCode)
        }
        return try decoder.decode(data: data, calendar: Calendar(identifier: .gregorian))
    }
}
