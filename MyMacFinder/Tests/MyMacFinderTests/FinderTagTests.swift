import XCTest
@testable import MyMacFinder

final class FinderTagTests: XCTestCase {
    func testNormalizesTagsByTrimmingSortingAndDeduplicatingCaseInsensitively() {
        let tags = FinderTag.normalized(["  Work ", "red", "WORK", "", "Client"])

        XCTAssertEqual(tags.map(\.name), ["Client", "red", "Work"])
    }

    func testIdentifierIsCaseInsensitiveName() {
        XCTAssertEqual(FinderTag(" Work ").id, "work")
    }
}
