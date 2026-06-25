import Foundation
import SwiftData

public enum HolidaySource: String, Codable, CaseIterable {
    case api
    case manual
}

@Model
public final class HolidayRecord {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var title: String
    public var sourceRaw: String
    public var providerKey: String
    public var isHidden: Bool
    public var year: Int
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        date: Date,
        title: String,
        source: HolidaySource,
        providerKey: String = "",
        isHidden: Bool = false,
        year: Int,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.sourceRaw = source.rawValue
        self.providerKey = providerKey
        self.isHidden = isHidden
        self.year = year
        self.updatedAt = updatedAt
    }

    public var source: HolidaySource {
        get { HolidaySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
