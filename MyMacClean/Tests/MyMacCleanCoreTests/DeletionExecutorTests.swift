import XCTest
@testable import MyMacCleanCore

final class DeletionExecutorTests: XCTestCase {
    func testExecutorPermanentlyRemovesPlannedFiles() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "executor")
        let appURL = root.appendingPathComponent("Figma.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.figma.Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: nil, executableName: "Figma", bundleURL: appURL, iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: cacheURL, kind: .cache, size: 0, matchReason: "test", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [candidate], createdAt: Date(timeIntervalSince1970: 0))

        let results = await DeletionExecutor().execute(plan: plan, confirmation: "DELETE")

        XCTAssertEqual(results, [DeletionItemResult(path: cacheURL.path, success: true, errorMessage: nil)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testExecutorRejectsMissingConfirmationPhrase() async throws {
        let app = InstalledApp(displayName: "Figma", bundleIdentifier: nil, version: nil, executableName: nil, bundleURL: URL(fileURLWithPath: "/tmp/Figma.app"), iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: URL(fileURLWithPath: "/tmp/Figma-cache"), kind: .cache, size: 0, matchReason: "test", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [candidate])

        let results = await DeletionExecutor().execute(plan: plan, confirmation: "delete figma")

        XCTAssertEqual(results, [DeletionItemResult(path: "/tmp/Figma-cache", success: false, errorMessage: "confirmation phrase mismatch")])
    }

    func testExecutorRejectsAppNameInConfirmationPhrase() async throws {
        let app = InstalledApp(displayName: "Figma", bundleIdentifier: nil, version: nil, executableName: nil, bundleURL: URL(fileURLWithPath: "/tmp/Figma.app"), iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: URL(fileURLWithPath: "/tmp/Figma-cache"), kind: .cache, size: 0, matchReason: "test", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [candidate])

        let results = await DeletionExecutor().execute(plan: plan, confirmation: "DELETE Figma")

        XCTAssertEqual(results, [DeletionItemResult(path: "/tmp/Figma-cache", success: false, errorMessage: "confirmation phrase mismatch")])
    }
}
