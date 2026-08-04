import Foundation
import SwiftData

public protocol PersistenceContext: AnyObject {
    func save() throws
    func rollback()
}

extension ModelContext: PersistenceContext {}

public enum PersistenceTransaction {
    public static func save(context: any PersistenceContext) throws {
#if MYMACCALENDAR_ENABLE_QA_FAULTS
        if ProcessInfo.processInfo.environment["MYMACCALENDAR_INJECT_SAVE_FAILURE"] == "1" {
            context.rollback()
            throw InjectedPersistenceFailure()
        }
#endif
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

#if MYMACCALENDAR_ENABLE_QA_FAULTS
private struct InjectedPersistenceFailure: LocalizedError {
    var errorDescription: String? { "QA 저장 실패가 주입되었습니다." }
}
#endif

public struct ExternalStateCompensationError: Error {
    public let persistenceError: any Error
    public let compensationError: any Error
}

public enum ExternalStateTransaction {
    public static func apply<Value>(
        previous: Value,
        desired: Value,
        applyExternal: (Value) throws -> Void,
        mutateLocal: (Value) -> Void,
        saveLocal: () throws -> Void
    ) throws {
        try applyExternal(desired)
        mutateLocal(desired)

        do {
            try saveLocal()
        } catch {
            let persistenceError = error
            do {
                try applyExternal(previous)
            } catch {
                throw ExternalStateCompensationError(
                    persistenceError: persistenceError,
                    compensationError: error
                )
            }
            throw persistenceError
        }
    }
}
