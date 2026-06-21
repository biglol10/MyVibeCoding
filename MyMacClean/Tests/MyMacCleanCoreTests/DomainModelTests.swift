import XCTest
@testable import MyMacCleanCore

final class DomainModelTests: XCTestCase {
    func testDeletionPlanTotalsSelectedCandidateSizes() {
        let app = InstalledApp(
            displayName: "Figma",
            bundleIdentifier: "com.figma.Desktop",
            version: "124.0",
            executableName: "Figma",
            bundleURL: URL(fileURLWithPath: "/Applications/Figma.app"),
            iconIdentifier: nil,
            bundleSize: 10,
            lastOpenedAt: nil
        )
        let support = RelatedFileCandidate(
            url: URL(fileURLWithPath: "/Users/me/Library/Application Support/Figma"),
            kind: .applicationSupport,
            size: 25,
            matchReason: "name match in Application Support",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let cache = RelatedFileCandidate(
            url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.figma.Desktop"),
            kind: .cache,
            size: 17,
            matchReason: "bundle identifier match in Caches",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )

        let plan = DeletionPlan(app: app, candidates: [support, cache], createdAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(plan.totalSize, 42)
    }
}
