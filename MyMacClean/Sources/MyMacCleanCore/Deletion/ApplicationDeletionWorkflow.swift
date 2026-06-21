import Foundation

public struct ApplicationDeletionWorkflow: Sendable {
    private let planner: DeletionPlanner

    public init(planner: DeletionPlanner = DeletionPlanner()) {
        self.planner = planner
    }

    public func makeDefaultPlan(app: InstalledApp, candidates: [RelatedFileCandidate]) throws -> DeletionPlan {
        let selectedIDs = Set(candidates.filter(\.defaultSelected).map(\.id))
        return try planner.makePlan(app: app, candidates: candidates, selectedIDs: selectedIDs)
    }
}
