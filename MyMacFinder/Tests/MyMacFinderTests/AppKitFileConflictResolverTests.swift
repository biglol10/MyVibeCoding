import AppKit
import Foundation
import XCTest
@testable import MyMacFinder

final class AppKitFileConflictResolverTests: XCTestCase {
    func testCopyConflictContentIncludesSkip() {
        let conflict = FileConflict(
            operation: .copy,
            sourceURL: URL(fileURLWithPath: "/tmp/source.txt"),
            destinationURL: URL(fileURLWithPath: "/tmp/Folder/source.txt"),
            itemIndex: 2,
            itemCount: 5
        )

        let content = FileConflictDialogContent(conflict: conflict)

        XCTAssertEqual(content.messageText, "Copy Conflict")
        XCTAssertTrue(content.informativeText.contains("source.txt"))
        XCTAssertTrue(content.informativeText.contains("/tmp/Folder"))
        XCTAssertTrue(content.informativeText.contains("Item 3 of 5"))
        XCTAssertEqual(content.buttonTitles, ["Replace", "Keep Both", "Skip", "Cancel"])
    }

    func testRenameConflictContentOmitsSkip() {
        let conflict = FileConflict(
            operation: .rename,
            sourceURL: URL(fileURLWithPath: "/tmp/source.txt"),
            destinationURL: URL(fileURLWithPath: "/tmp/Folder/source.txt"),
            itemIndex: 0,
            itemCount: 1
        )

        let content = FileConflictDialogContent(conflict: conflict)

        XCTAssertEqual(content.messageText, "Rename Conflict")
        XCTAssertEqual(content.buttonTitles, ["Replace", "Keep Both", "Cancel"])
    }

    func testDecisionMappingTreatsRenameThirdButtonAsCancel() throws {
        let copyConflict = FileConflict(
            operation: .copy,
            sourceURL: URL(fileURLWithPath: "/tmp/source.txt"),
            destinationURL: URL(fileURLWithPath: "/tmp/Folder/source.txt"),
            itemIndex: 0,
            itemCount: 1
        )
        let renameConflict = FileConflict(
            operation: .rename,
            sourceURL: URL(fileURLWithPath: "/tmp/source.txt"),
            destinationURL: URL(fileURLWithPath: "/tmp/Folder/source.txt"),
            itemIndex: 0,
            itemCount: 1
        )

        XCTAssertEqual(
            try FileConflictDialogContent.decision(for: .alertFirstButtonReturn, conflict: copyConflict),
            .replace
        )
        XCTAssertEqual(
            try FileConflictDialogContent.decision(for: .alertSecondButtonReturn, conflict: copyConflict),
            .keepBoth
        )
        XCTAssertEqual(
            try FileConflictDialogContent.decision(for: .alertThirdButtonReturn, conflict: copyConflict),
            .skip
        )
        XCTAssertThrowsError(
            try FileConflictDialogContent.decision(for: .alertThirdButtonReturn, conflict: renameConflict)
        ) { error in
            XCTAssertEqual(error as? FileOperationCancellation, FileOperationCancellation(operation: .rename))
        }
    }
}
