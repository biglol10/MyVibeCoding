import Foundation
import XCTest
@testable import MyMacFinder

final class SortEngineTests: XCTestCase {
    func testFoldersFirstNameAscending() {
        let entries = [
            entry("z-file.txt", kind: .file),
            entry("b-folder", kind: .folder),
            entry("a-file.txt", kind: .file),
            entry("a-folder", kind: .folder)
        ]

        let result = SortEngine.sorted(
            entries,
            descriptor: EntrySortDescriptor(key: .name, direction: .ascending, folderFileOrdering: .foldersFirst)
        )

        XCTAssertEqual(result.map(\.name), ["a-folder", "b-folder", "a-file.txt", "z-file.txt"])
    }

    func testFilesFirstSizeDescending() {
        let entries = [
            entry("folder", kind: .folder, size: nil),
            entry("small.txt", kind: .file, size: 10),
            entry("large.txt", kind: .file, size: 100)
        ]

        let result = SortEngine.sorted(
            entries,
            descriptor: EntrySortDescriptor(key: .size, direction: .descending, folderFileOrdering: .filesFirst)
        )

        XCTAssertEqual(result.map(\.name), ["large.txt", "small.txt", "folder"])
    }

    func testGroupsByKind() {
        let entries = [
            entry("photo.png", kind: .file, typeDescription: "PNG image"),
            entry("src", kind: .folder, typeDescription: "Folder"),
            entry("notes.md", kind: .file, typeDescription: "Markdown document")
        ]

        let groups = SortEngine.group(entries, descriptor: EntryGroupDescriptor(key: .kind))

        XCTAssertEqual(groups.map(\.title), ["Folder", "Markdown document", "PNG image"])
        XCTAssertEqual(groups.first?.entries.map(\.name), ["src"])
    }

    private func entry(
        _ name: String,
        kind: FileEntryKind,
        typeDescription: String = "File",
        size: Int64? = nil
    ) -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            kind: kind,
            typeDescription: typeDescription,
            fileExtension: URL(fileURLWithPath: name).pathExtension.lowercased(),
            size: size,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: name.hasPrefix("."),
            isDirectoryLike: kind == .folder,
            isReadable: true
        )
    }
}
