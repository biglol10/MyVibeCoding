import Foundation
import SwiftData

public final class SettingsStore {
    private let context: ModelContext
    private let saveTransaction: (ModelContext) throws -> Void

    public init(context: ModelContext) {
        self.context = context
        self.saveTransaction = { try PersistenceTransaction.save(context: $0) }
    }

    init(context: ModelContext, saveTransaction: @escaping (ModelContext) throws -> Void) {
        self.context = context
        self.saveTransaction = saveTransaction
    }

    public func load() throws -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>(predicate: #Predicate { $0.id == "default" })
        if let existing = try context.fetch(descriptor).first {
            if SettingsValidation.repair(existing) {
                try saveTransaction(context)
            }
            return existing
        }

        let settings = AppSettings()
        context.insert(settings)
        try saveTransaction(context)
        return settings
    }
}
