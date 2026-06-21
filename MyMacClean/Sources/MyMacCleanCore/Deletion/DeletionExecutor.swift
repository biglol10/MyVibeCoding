import Foundation

public struct DeletionExecutor: Sendable {
    public init() {}

    public func requiredConfirmationPhrase(for app: InstalledApp) -> String {
        "DELETE"
    }

    public func execute(plan: DeletionPlan, confirmation: String) async -> [DeletionItemResult] {
        guard confirmation == requiredConfirmationPhrase(for: plan.app) else {
            return plan.candidates.map {
                DeletionItemResult(path: $0.url.path, success: false, errorMessage: "confirmation phrase mismatch")
            }
        }

        return plan.candidates.map { candidate in
            do {
                if FileManager.default.fileExists(atPath: candidate.url.path) {
                    try FileManager.default.removeItem(at: candidate.url)
                }
                return DeletionItemResult(path: candidate.url.path, success: true, errorMessage: nil)
            } catch {
                return DeletionItemResult(path: candidate.url.path, success: false, errorMessage: error.localizedDescription)
            }
        }
    }
}
