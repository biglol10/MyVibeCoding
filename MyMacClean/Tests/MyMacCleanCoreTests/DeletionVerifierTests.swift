import XCTest
@testable import MyMacCleanCore

final class DeletionVerifierTests: XCTestCase {
    func testVerifierClassifiesDeletedAndStillExistingPaths() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "verifier")
        let deletedURL = root.appendingPathComponent("deleted-cache", isDirectory: true)
        let remainingURL = root.appendingPathComponent("remaining-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: deletedURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remainingURL, withIntermediateDirectories: true)

        let app = InstalledApp(
            displayName: "Verifier",
            bundleIdentifier: "com.example.verifier",
            version: nil,
            executableName: nil,
            bundleURL: root.appendingPathComponent("Verifier.app"),
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )
        let deletedCandidate = RelatedFileCandidate(
            url: deletedURL,
            kind: .cache,
            size: 1,
            matchReason: "test",
            confidence: .high,
            safety: .safe,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let remainingCandidate = RelatedFileCandidate(
            url: remainingURL,
            kind: .cache,
            size: 1,
            matchReason: "test",
            confidence: .high,
            safety: .safe,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let plan = DeletionPlan(app: app, candidates: [deletedCandidate, remainingCandidate])
        try FileManager.default.removeItem(at: deletedURL)

        let results = await DeletionVerifier().verify(plan: plan)

        XCTAssertEqual(results.map(\.status), [.deleted, .stillExists])
        XCTAssertEqual(results.map(\.path), [deletedURL.path, remainingURL.path])
    }

    func testVerifierClassifiesSkippedCandidates() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "verifier-skipped")
        let skippedURL = root.appendingPathComponent("skipped-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: skippedURL, withIntermediateDirectories: true)

        let candidate = RelatedFileCandidate(
            url: skippedURL,
            kind: .cache,
            size: 1,
            matchReason: "test",
            confidence: .high,
            safety: .safe,
            defaultSelected: false,
            requiresManualReview: false,
            isProtected: false
        )
        let result = await DeletionVerifier().verify(candidate: candidate, wasSelected: false)

        XCTAssertEqual(result.status, .skipped)
        XCTAssertEqual(result.path, skippedURL.path)
    }

    func testVerifierClassifiesPathsMissingBeforeDeleteFromExecutionResults() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "verifier-missing-before-delete")
        let missingURL = root.appendingPathComponent("missing-cache", isDirectory: true)
        let app = InstalledApp(
            displayName: "Verifier",
            bundleIdentifier: "com.example.verifier",
            version: nil,
            executableName: nil,
            bundleURL: root.appendingPathComponent("Verifier.app"),
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )
        let candidate = RelatedFileCandidate(
            url: missingURL,
            kind: .cache,
            size: 1,
            matchReason: "test",
            confidence: .high,
            safety: .safe,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let plan = DeletionPlan(app: app, candidates: [candidate])
        let executionResults = [
            DeletionItemResult(path: missingURL.path, success: false, errorMessage: "path not found before delete")
        ]

        let results = await DeletionVerifier().verify(plan: plan, executionResults: executionResults)

        XCTAssertEqual(results, [
            DeletionVerificationResult(path: missingURL.path, status: .notFoundBeforeDelete, errorMessage: "path not found before delete")
        ])
    }
}
