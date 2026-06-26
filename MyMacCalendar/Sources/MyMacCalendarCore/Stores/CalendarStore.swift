import Foundation
import SwiftData

public enum CalendarStore {
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            CalendarEvent.self,
            HolidayRecord.self,
            AppSettings.self
        ])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let storeURL = try persistentStoreURL()
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    public static func makeInMemoryContainer() throws -> ModelContainer {
        try makeContainer(inMemory: true)
    }

    private static func persistentStoreURL() throws -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = baseURL.appendingPathComponent("MyMacCalendar", isDirectory: true)
        if try prepareWritableDirectory(appDirectory) {
            return appDirectory.appendingPathComponent("MyMacCalendar.store")
        }

        let fallbackDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCalendar", isDirectory: true)
        try FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
        return fallbackDirectory.appendingPathComponent("MyMacCalendar.store")
    }

    private static func prepareWritableDirectory(_ directory: URL) throws -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let testURL = directory.appendingPathComponent(".write-test")
            try Data().write(to: testURL, options: [.atomic])
            try? FileManager.default.removeItem(at: testURL)
            return true
        } catch CocoaError.fileWriteNoPermission {
            return false
        } catch CocoaError.fileNoSuchFile {
            return false
        } catch {
            throw error
        }
    }
}
