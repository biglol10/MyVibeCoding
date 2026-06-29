import XCTest
@testable import MyMacFinder

final class FileDropModelTests: XCTestCase {
    func testOptionModifierForcesCopy() {
        XCTAssertEqual(
            FileDropOperationResolver.operation(source: .local, optionKeyPressed: true, proposedOperation: nil),
            .copy
        )
        XCTAssertEqual(
            FileDropOperationResolver.operation(source: .external, optionKeyPressed: true, proposedOperation: .move),
            .copy
        )
    }

    func testLocalDropDefaultsToMove() {
        XCTAssertEqual(
            FileDropOperationResolver.operation(source: .local, optionKeyPressed: false, proposedOperation: nil),
            .move
        )
    }

    func testExternalDropDefaultsToCopy() {
        XCTAssertEqual(
            FileDropOperationResolver.operation(source: .external, optionKeyPressed: false, proposedOperation: nil),
            .copy
        )
    }

    func testExternalDropIgnoresExplicitMoveProposal() {
        XCTAssertEqual(
            FileDropOperationResolver.operation(source: .external, optionKeyPressed: false, proposedOperation: .move),
            .copy
        )
    }
}
