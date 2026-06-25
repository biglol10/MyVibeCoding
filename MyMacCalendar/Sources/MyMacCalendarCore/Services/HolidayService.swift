import Foundation

public struct HolidayImport: Equatable {
    public let date: Date
    public let title: String
    public let providerKey: String

    public init(date: Date, title: String, providerKey: String) {
        self.date = date
        self.title = title
        self.providerKey = providerKey
    }
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
        formatter.dateFormat = "yyyy-MM-dd"

        return try JSONDecoder().decode([NagerHolidayDTO].self, from: data).compactMap { dto in
            guard let date = formatter.date(from: dto.date) else { return nil }
            let normalized = calendar.startOfDay(for: date)
            return HolidayImport(date: normalized, title: dto.localName, providerKey: "\(dto.date)-\(dto.localName)")
        }
    }
}

public struct HolidayMerger {
    public init() {}

    public func merge(imports: [HolidayImport], existing: [HolidayRecord], year: Int) -> [HolidayRecord] {
        let hiddenKeys = Set(existing.filter { $0.source == .api && $0.isHidden }.map(\.providerKey))
        let manualByDate = Dictionary(grouping: existing.filter { $0.source == .manual && $0.year == year }, by: { dayKey($0.date) })
            .compactMapValues { $0.sorted { $0.updatedAt > $1.updatedAt }.first }

        var merged: [HolidayRecord] = []
        for item in imports where hiddenKeys.contains(item.providerKey) == false {
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
}

public struct HolidayService {
    private let session: URLSession
    private let decoder: NagerHolidayDecoder

    public init(session: URLSession = .shared, decoder: NagerHolidayDecoder = NagerHolidayDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    public func fetchKoreanHolidays(year: Int) async throws -> [HolidayImport] {
        let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/KR")!
        let (data, _) = try await session.data(from: url)
        return try decoder.decode(data: data, calendar: Calendar(identifier: .gregorian))
    }
}
