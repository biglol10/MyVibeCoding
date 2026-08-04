import Foundation
import SwiftData

enum CalendarStoreError: Error {
    case applicationSupportDirectoryUnavailable
}

public enum CalendarStore {
    public static func makeContainer() throws -> ModelContainer {
        let storeURL = try persistentStoreURL()
        return try makeContainer(at: storeURL)
    }

    static func makeContainer(at storeURL: URL) throws -> ModelContainer {
        try prepareWritableDirectory(storeURL.deletingLastPathComponent())
        let schema = Schema(versionedSchema: CalendarSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: CalendarSchemaMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CalendarSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: CalendarSchemaMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func persistentStoreURL() throws -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["MYMACCALENDAR_STORE_URL"], overridePath.isEmpty == false {
            let overrideURL = URL(fileURLWithPath: overridePath)
            let directory = overrideURL.deletingLastPathComponent()
            try prepareWritableDirectory(directory)
            return overrideURL
        }

        guard let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CalendarStoreError.applicationSupportDirectoryUnavailable
        }
        let appDirectory = baseURL.appendingPathComponent("MyMacCalendar", isDirectory: true)
        try prepareWritableDirectory(appDirectory)
        return appDirectory.appendingPathComponent("MyMacCalendar.store")
    }

    private static func prepareWritableDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let testURL = directory.appendingPathComponent(".write-test-\(UUID().uuidString)")
        try Data().write(to: testURL, options: [.atomic])
        try FileManager.default.removeItem(at: testURL)
    }
}
