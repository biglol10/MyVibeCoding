import XCTest
@testable import MyMacSearchAppSupport

final class ResultKeyboardCommandTests: XCTestCase {
    func testUnmodifiedSpaceResolvesToQuickLook() {
        XCTAssertEqual(
            ResultKeyboardCommand.resolve(characters: " ", hasModifiers: false),
            .quickLook
        )
    }

    func testModifiedSpaceAndOtherCharactersRemainUnhandled() {
        XCTAssertNil(ResultKeyboardCommand.resolve(characters: " ", hasModifiers: true))
        XCTAssertNil(ResultKeyboardCommand.resolve(characters: "q", hasModifiers: false))
        XCTAssertNil(ResultKeyboardCommand.resolve(characters: "", hasModifiers: false))
    }
}
