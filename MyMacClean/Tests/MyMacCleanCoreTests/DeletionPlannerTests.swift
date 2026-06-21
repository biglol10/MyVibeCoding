import XCTest
@testable import MyMacCleanCore

final class DeletionPlannerTests: XCTestCase {
    func testPlannerExcludesProtectedAndUnselectedCandidates() throws {
        let app = InstalledApp(
            displayName: "Figma",
            bundleIdentifier: "com.figma.Desktop",
            version: nil,
            executableName: "Figma",
            bundleURL: URL(fileURLWithPath: "/Applications/Figma.app"),
            iconIdentifier: nil,
            bundleSize: 10,
            lastOpenedAt: nil
        )
        let selected = candidate(path: "/Users/me/Library/Caches/com.figma.Desktop", selected: true, protected: false, size: 5)
        let unselected = candidate(path: "/Users/me/Library/Logs/Figma", selected: false, protected: false, size: 7)
        let protected = candidate(path: "/Users/me/Documents/Figma Export.fig", selected: true, protected: true, size: 11)

        let plan = try DeletionPlanner().makePlan(app: app, candidates: [selected, unselected, protected], selectedIDs: [selected.id, protected.id])

        XCTAssertEqual(plan.candidates.map(\.url.path), ["/Users/me/Library/Caches/com.figma.Desktop"])
        XCTAssertEqual(plan.totalSize, 5)
    }

    private func candidate(path: String, selected: Bool, protected: Bool, size: Int64) -> RelatedFileCandidate {
        RelatedFileCandidate(
            url: URL(fileURLWithPath: path),
            kind: .cache,
            size: size,
            matchReason: "test",
            confidence: .high,
            defaultSelected: selected,
            requiresManualReview: protected,
            isProtected: protected
        )
    }
}
