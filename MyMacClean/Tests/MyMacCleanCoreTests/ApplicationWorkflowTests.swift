import XCTest
@testable import MyMacCleanCore

final class ApplicationWorkflowTests: XCTestCase {
    func testWorkflowBuildsDeletionPlanFromDefaultSelectedCandidates() throws {
        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: nil, executableName: "Figma", bundleURL: URL(fileURLWithPath: "/Applications/Figma.app"), iconIdentifier: nil, bundleSize: 10, lastOpenedAt: nil)
        let selected = RelatedFileCandidate(url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.figma.Desktop"), kind: .cache, size: 5, matchReason: "bundle identifier match", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let ignored = RelatedFileCandidate(url: URL(fileURLWithPath: "/Users/me/Documents/Figma Export.fig"), kind: .unknown, size: 8, matchReason: "app name token match", confidence: .low, defaultSelected: false, requiresManualReview: true, isProtected: true)

        let plan = try ApplicationDeletionWorkflow().makeDefaultPlan(app: app, candidates: [selected, ignored])

        XCTAssertEqual(plan.candidates, [selected])
    }
}
