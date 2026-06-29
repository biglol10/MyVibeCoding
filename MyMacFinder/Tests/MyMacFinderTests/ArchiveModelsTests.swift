import Foundation
import XCTest
@testable import MyMacFinder

final class ArchiveModelsTests: XCTestCase {
    func testArchiveLocationNormalizesInternalPaths() {
        let archiveURL = URL(fileURLWithPath: "/tmp/sample.zip")

        XCTAssertEqual(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "").internalPath,
            ""
        )
        XCTAssertEqual(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "/docs/readme.txt").internalPath,
            "docs/readme.txt"
        )
        XCTAssertEqual(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "docs//nested/").internalPath,
            "docs/nested"
        )
    }

    func testArchiveDisplayPathUsesHostZipPathAndInternalPath() {
        let archiveURL = URL(fileURLWithPath: "/tmp/sample.zip")

        XCTAssertEqual(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "").displayPath,
            "/tmp/sample.zip/"
        )
        XCTAssertEqual(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt").displayPath,
            "/tmp/sample.zip/docs/readme.txt"
        )
    }

    func testArchiveParentNavigationStaysInsideArchive() {
        let archiveURL = URL(fileURLWithPath: "/tmp/sample.zip")
        let nested = ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/guides")
        let root = ArchiveLocation(archiveURL: archiveURL, internalPath: "")

        XCTAssertEqual(nested.parent, ArchiveLocation(archiveURL: archiveURL, internalPath: "docs"))
        XCTAssertEqual(root.parent, root)
    }

    func testPaneLocationDisplayPathAndArchiveFlag() {
        let folderURL = URL(fileURLWithPath: "/Users/biglol")
        let archiveURL = URL(fileURLWithPath: "/tmp/sample.zip")

        XCTAssertEqual(PaneLocation.fileSystem(folderURL).displayPath, "/Users/biglol")
        XCTAssertFalse(PaneLocation.fileSystem(folderURL).isArchive)

        let archive = PaneLocation.archive(ArchiveLocation(archiveURL: archiveURL, internalPath: "docs"))
        XCTAssertEqual(archive.displayPath, "/tmp/sample.zip/docs")
        XCTAssertTrue(archive.isArchive)
    }

    func testFileEntryDefaultsToFileSystemSource() {
        let url = URL(fileURLWithPath: "/tmp/note.txt")
        let entry = FileEntry(
            url: url,
            name: "note.txt",
            kind: .file,
            typeDescription: "Plain Text Document",
            fileExtension: "txt",
            size: 4,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )

        XCTAssertEqual(entry.source, .fileSystem)
        XCTAssertFalse(entry.isArchiveBacked)
    }
}
