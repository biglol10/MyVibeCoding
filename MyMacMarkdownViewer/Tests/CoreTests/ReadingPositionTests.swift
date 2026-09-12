import XCTest
@testable import MyMarkdownCore

final class ReadingPositionTests: XCTestCase {
    func testStoredPositionSurvivesAndDefaultsHeadToAnchor() {
        let value = ReadingPosition(values: ["anchor": 7, "scrollTop": 1240.5], textLength: 20)
        XCTAssertEqual(value.anchor, 7); XCTAssertEqual(value.head, 7)
        XCTAssertEqual(value.scrollTop, 1240.5)
    }
    func testChangedDocumentAndInvalidPersistedNumbersAreClamped() {
        let shorter = ReadingPosition(values: ["anchor": 100, "head": -2, "scrollTop": -3], textLength: 10)
        XCTAssertEqual(shorter.anchor, 10); XCTAssertEqual(shorter.head, 0); XCTAssertEqual(shorter.scrollTop, 0)
        let invalid = ReadingPosition(values: ["anchor": .infinity, "head": .nan, "scrollTop": .infinity], textLength: 0)
        XCTAssertEqual(invalid, ReadingPosition(values: [:], textLength: 0))
    }
}
