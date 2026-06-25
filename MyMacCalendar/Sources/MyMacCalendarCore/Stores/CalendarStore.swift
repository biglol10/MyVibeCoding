import Foundation
import SwiftData

public enum CalendarStore {
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            CalendarEvent.self,
            HolidayRecord.self,
            AppSettings.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    public static func makeInMemoryContainer() throws -> ModelContainer {
        try makeContainer(inMemory: true)
    }
}
