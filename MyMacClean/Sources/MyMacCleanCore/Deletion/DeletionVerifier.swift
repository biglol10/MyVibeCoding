import Foundation

public struct DeletionVerifier: Sendable {
    public init() {}

    public func verify(plan: DeletionPlan) async -> [DeletionVerificationResult] {
        plan.candidates.map { candidate in
            verifyExistingPath(candidate.url)
        }
    }

    public func verify(candidate: RelatedFileCandidate, wasSelected: Bool) async -> DeletionVerificationResult {
        guard wasSelected else {
            return DeletionVerificationResult(path: candidate.url.path, status: .skipped, errorMessage: nil)
        }
        return verifyExistingPath(candidate.url)
    }

    private func verifyExistingPath(_ url: URL) -> DeletionVerificationResult {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else {
            return DeletionVerificationResult(path: url.path, status: .deleted, errorMessage: nil)
        }

        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return DeletionVerificationResult(path: url.path, status: .stillExists, errorMessage: nil)
        } catch {
            return DeletionVerificationResult(path: url.path, status: .permissionDenied, errorMessage: error.localizedDescription)
        }
    }
}
