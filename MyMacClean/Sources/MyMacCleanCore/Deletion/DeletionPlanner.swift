import Foundation

public enum DeletionPlannerError: LocalizedError, Equatable {
    case emptySelection

    public var errorDescription: String? {
        switch self {
        case .emptySelection:
            "Select at least one deletable item."
        }
    }
}

public struct DeletionPlanner: Sendable {
    public init() {}

    public func makePlan(
        app: InstalledApp,
        candidates: [RelatedFileCandidate],
        selectedIDs: Set<RelatedFileCandidate.ID>,
        createdAt: Date = Date()
    ) throws -> DeletionPlan {
        let selected = candidates
            .filter { selectedIDs.contains($0.id) }
            .filter { !$0.isProtected }

        guard !selected.isEmpty else {
            throw DeletionPlannerError.emptySelection
        }

        return DeletionPlan(app: app, candidates: selected, createdAt: createdAt)
    }
}
