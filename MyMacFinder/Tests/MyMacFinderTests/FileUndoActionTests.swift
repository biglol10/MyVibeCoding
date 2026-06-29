import XCTest
@testable import MyMacFinder

final class FileUndoActionTests: XCTestCase {
    func testUndoActionTitlesDescribeUserOperation() {
        XCTAssertEqual(FileUndoAction.created([URL(fileURLWithPath: "/tmp/a")]).title, "Undo Create")
        XCTAssertEqual(FileUndoAction.copied([URL(fileURLWithPath: "/tmp/a")]).title, "Undo Copy")
        XCTAssertEqual(
            FileUndoAction.moved([
                FileMoveRecord(
                    source: URL(fileURLWithPath: "/tmp/a"),
                    destination: URL(fileURLWithPath: "/tmp/b")
                )
            ]).title,
            "Undo Move"
        )
        XCTAssertEqual(
            FileUndoAction.renamed(
                FileMoveRecord(
                    source: URL(fileURLWithPath: "/tmp/a"),
                    destination: URL(fileURLWithPath: "/tmp/b")
                )
            ).title,
            "Undo Rename"
        )
    }
}
