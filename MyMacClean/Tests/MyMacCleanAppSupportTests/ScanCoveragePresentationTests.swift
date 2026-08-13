import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

final class ScanCoveragePresentationTests: XCTestCase {
    func testCoveragePresentationSummarizesAndSortsIssues() {
        let permissionIssue = ScanIssue(
            path: "/Users/test/Library/Caches",
            message: "Permission denied",
            permissionRelated: true
        )
        let corruptIssue = ScanIssue(
            path: "/Applications/Broken.app",
            message: "Info.plist is unreadable",
            permissionRelated: false
        )

        let presentation = ScanCoveragePresentation(issues: [permissionIssue, corruptIssue])

        XCTAssertEqual(presentation.title, "Scan incomplete")
        XCTAssertEqual(presentation.summary, "2 locations could not be inspected.")
        XCTAssertTrue(presentation.showsFullDiskAccessAction)
        XCTAssertEqual(presentation.detailLines, presentation.detailLines.sorted())
        XCTAssertEqual(
            presentation.copyText,
            "Scan incomplete\n2 locations could not be inspected.\n\n" + presentation.detailLines.joined(separator: "\n")
        )
    }

    func testCoveragePresentationUsesSingularCopyWithoutPermissionAction() {
        let issue = ScanIssue(
            path: "/Applications/Broken.app",
            message: "Info.plist is unreadable",
            permissionRelated: false
        )

        let presentation = ScanCoveragePresentation(issues: [issue])

        XCTAssertEqual(presentation.summary, "1 location could not be inspected.")
        XCTAssertFalse(presentation.showsFullDiskAccessAction)
        XCTAssertEqual(presentation.detailLines, ["/Applications/Broken.app - Info.plist is unreadable"])
    }
}
