import Foundation
import XCTest
@testable import MyMacFinder

final class FileEntrySearchFilterTests: XCTestCase {
    func testEmptyQueryReturnsAllEntries() {
        let entries = [
            entry("Report.pdf", typeDescription: "PDF document"),
            entry("Screenshots", kind: .folder, typeDescription: "Folder")
        ]

        let result = FileEntrySearchFilter.filtered(entries, query: "   ")

        XCTAssertEqual(result.map(\.name), ["Report.pdf", "Screenshots"])
    }

    func testMatchesNameExtensionAndTypeDescriptionCaseInsensitively() {
        let entries = [
            entry("Report.pdf", typeDescription: "PDF document"),
            entry("holiday.JPG", typeDescription: "JPEG image"),
            entry("Screenshots", kind: .folder, typeDescription: "Folder"),
            entry("notes.md", typeDescription: "Markdown document")
        ]

        XCTAssertEqual(FileEntrySearchFilter.filtered(entries, query: "report").map(\.name), ["Report.pdf"])
        XCTAssertEqual(FileEntrySearchFilter.filtered(entries, query: "jpg").map(\.name), ["holiday.JPG"])
        XCTAssertEqual(FileEntrySearchFilter.filtered(entries, query: "folder").map(\.name), ["Screenshots"])
    }

    func testQueryMatchesFinderTags() {
        let entries = [
            entry("Report.pdf", typeDescription: "PDF document", finderTags: [FinderTag("Work")]),
            entry("notes.md", typeDescription: "Markdown document", finderTags: [FinderTag("Personal")])
        ]

        XCTAssertEqual(FileEntrySearchFilter.filtered(entries, query: "work").map(\.name), ["Report.pdf"])
    }

    func testCriteriaFiltersByKindAndExtension() {
        let entries = [
            entry("Report.pdf", typeDescription: "PDF document"),
            entry("Report.txt", typeDescription: "Plain text"),
            entry("Report Folder", kind: .folder, typeDescription: "Folder")
        ]

        XCTAssertEqual(
            FileEntrySearchFilter.filtered(
                entries,
                criteria: FileEntrySearchCriteria(query: "report", kind: .files, fileExtension: "pdf")
            ).map(\.name),
            ["Report.pdf"]
        )
        XCTAssertEqual(
            FileEntrySearchFilter.filtered(
                entries,
                criteria: FileEntrySearchCriteria(query: "report", kind: .folders)
            ).map(\.name),
            ["Report Folder"]
        )
    }

    func testCriteriaFiltersByFinderTag() {
        let entries = [
            entry("Report.pdf", typeDescription: "PDF document", finderTags: [FinderTag("Work")]),
            entry("notes.md", typeDescription: "Markdown document", finderTags: [FinderTag("Personal")])
        ]

        XCTAssertEqual(
            FileEntrySearchFilter.filtered(
                entries,
                criteria: FileEntrySearchCriteria(tagQuery: "work")
            ).map(\.name),
            ["Report.pdf"]
        )
    }

    private func entry(
        _ name: String,
        kind: FileEntryKind = .file,
        typeDescription: String = "File",
        finderTags: [FinderTag] = []
    ) -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            kind: kind,
            typeDescription: typeDescription,
            fileExtension: URL(fileURLWithPath: name).pathExtension.lowercased(),
            size: nil,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: name.hasPrefix("."),
            isDirectoryLike: kind == .folder || kind == .zipVirtualFolder,
            isReadable: true,
            finderTags: finderTags
        )
    }
}
