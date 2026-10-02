import Foundation

public struct DefaultFileConflictResolver: FileConflictResolving {
    private let decision: FileConflictDecision

    public init(decision: FileConflictDecision = .keepBoth) {
        self.decision = decision
    }

    public func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision {
        if decision == .cancel {
            throw FileOperationCancellation(operation: conflict.operation)
        }
        return decision
    }
}
