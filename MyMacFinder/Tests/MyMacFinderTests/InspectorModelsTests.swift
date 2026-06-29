import Foundation
import XCTest
@testable import MyMacFinder

final class InspectorModelsTests: XCTestCase {
    func testSingleItemDetailsFormatMissingValuesAndBooleans() {
        let entry = makeEntry(
            name: ".config",
            kind: .file,
            typeDescription: "Plain Text",
            fileExtension: "",
            size: nil,
            dateCreated: nil,
            dateModified: Date(timeIntervalSince1970: 1_704_067_200),
            dateAccessed: nil,
            isHidden: true,
            isDirectoryLike: false,
            isReadable: false
        )

        let details = InspectorItemDetails(entry: entry)

        XCTAssertEqual(details.name, ".config")
        XCTAssertEqual(details.kind, "Plain Text")
        XCTAssertEqual(details.fileExtension, "--")
        XCTAssertEqual(details.sizeText, "--")
        XCTAssertEqual(details.dateCreatedText, "--")
        XCTAssertEqual(details.dateModifiedText, "2024-01-01 00:00")
        XCTAssertEqual(details.dateAccessedText, "--")
        XCTAssertEqual(details.path, entry.url.path)
        XCTAssertEqual(details.isHiddenText, "Yes")
        XCTAssertEqual(details.isReadableText, "No")
        XCTAssertFalse(details.isDirectoryLike)
    }

    func testSingleItemDetailsUseCalculatedFolderSizeWhenProvided() {
        let folder = makeEntry(
            name: "Project",
            kind: .folder,
            typeDescription: "Folder",
            fileExtension: "",
            size: nil,
            dateCreated: nil,
            dateModified: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: true,
            isReadable: true
        )

        let details = InspectorItemDetails(entry: folder, calculatedFolderSize: 12_345)

        XCTAssertEqual(details.sizeText, "12 KB")
        XCTAssertTrue(details.isDirectoryLike)
    }

    func testSingleItemDetailsFormatsFinderTags() {
        let entry = makeEntry(
            name: "tagged.txt",
            kind: .file,
            typeDescription: "Text",
            fileExtension: "txt",
            isDirectoryLike: false,
            finderTags: [FinderTag("Work"), FinderTag("Red")]
        )

        let details = InspectorItemDetails(entry: entry)

        XCTAssertEqual(details.finderTagsText, "Red, Work")
    }

    func testSelectionSummaryCountsFilesFoldersAndKnownFileSizes() {
        let parent = URL(fileURLWithPath: "/tmp/MyMacFinderSummary", isDirectory: true)
        let file = makeEntry(
            url: parent.appendingPathComponent("note.txt"),
            name: "note.txt",
            kind: .file,
            typeDescription: "Text",
            fileExtension: "txt",
            size: 10,
            isDirectoryLike: false
        )
        let folder = makeEntry(
            url: parent.appendingPathComponent("Sources", isDirectory: true),
            name: "Sources",
            kind: .folder,
            typeDescription: "Folder",
            fileExtension: "",
            size: nil,
            isDirectoryLike: true
        )

        let summary = InspectorSelectionSummary(entries: [file, folder])

        XCTAssertEqual(summary.itemCount, 2)
        XCTAssertEqual(summary.fileCount, 1)
        XCTAssertEqual(summary.folderCount, 1)
        XCTAssertEqual(summary.knownTotalSizeText, "10 bytes")
        XCTAssertEqual(summary.commonParentPath, parent.path)
        XCTAssertEqual(summary.previewNames, ["note.txt", "Sources"])
    }

    func testSelectionSummaryOmitsCommonParentWhenParentsDiffer() {
        let first = makeEntry(
            url: URL(fileURLWithPath: "/tmp/one/a.txt"),
            name: "a.txt",
            kind: .file,
            typeDescription: "Text",
            fileExtension: "txt",
            size: 1,
            isDirectoryLike: false
        )
        let second = makeEntry(
            url: URL(fileURLWithPath: "/tmp/two/b.txt"),
            name: "b.txt",
            kind: .file,
            typeDescription: "Text",
            fileExtension: "txt",
            size: 2,
            isDirectoryLike: false
        )

        let summary = InspectorSelectionSummary(entries: [first, second])

        XCTAssertNil(summary.commonParentPath)
        XCTAssertEqual(summary.knownTotalSizeText, "3 bytes")
    }

    private func makeEntry(
        url: URL = URL(fileURLWithPath: "/tmp/item"),
        name: String,
        kind: FileEntryKind,
        typeDescription: String,
        fileExtension: String,
        size: Int64? = nil,
        dateCreated: Date? = nil,
        dateModified: Date? = nil,
        dateAccessed: Date? = nil,
        isHidden: Bool = false,
        isDirectoryLike: Bool,
        isReadable: Bool = true,
        finderTags: [FinderTag] = []
    ) -> FileEntry {
        FileEntry(
            url: url,
            name: name,
            kind: kind,
            typeDescription: typeDescription,
            fileExtension: fileExtension,
            size: size,
            dateModified: dateModified,
            dateCreated: dateCreated,
            dateAccessed: dateAccessed,
            isHidden: isHidden,
            isDirectoryLike: isDirectoryLike,
            isReadable: isReadable,
            finderTags: finderTags
        )
    }
}
