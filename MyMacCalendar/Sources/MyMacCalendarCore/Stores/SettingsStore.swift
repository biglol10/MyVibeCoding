import Foundation
import SwiftData

public final class SettingsStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func load() throws -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>(predicate: #Predicate { $0.id == "default" })
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }
}
