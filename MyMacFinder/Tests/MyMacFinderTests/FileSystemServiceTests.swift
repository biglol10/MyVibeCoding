import Foundation
import XCTest
@testable import MyMacFinder

final class FileSystemServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testReadsVisibleFilesAndFolders() async throws {
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try "hello".write(to: tempDirectory.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let service = FileSystemService()
        let entries = try await service.contentsOfDirectory(at: tempDirectory, options: DirectoryReadOptions(showHiddenFiles: false))

        XCTAssertEqual(Set(entries.map(\.name)), ["Folder", "note.txt"])
        XCTAssertTrue(entries.first { $0.name == "Folder" }?.isDirectoryLike == true)
        XCTAssertEqual(entries.first { $0.name == "note.txt" }?.fileExtension, "txt")
    }

    func testFiltersDotHiddenFilesWhenHiddenFilesAreDisabled() async throws {
        try "secret".write(to: tempDirectory.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "public".write(to: tempDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let service = FileSystemService()
        let entries = try await service.contentsOfDirectory(at: tempDirectory, options: DirectoryReadOptions(showHiddenFiles: false))

        XCTAssertEqual(entries.map(\.name), ["README.md"])
    }

    func testIncludesHiddenFilesWhenEnabled() async throws {
        try "secret".write(to: tempDirectory.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let service = FileSystemService()
        let entries = try await service.contentsOfDirectory(at: tempDirectory, options: DirectoryReadOptions(showHiddenFiles: true))

        XCTAssertEqual(entries.map(\.name), [".env"])
        XCTAssertTrue(entries[0].isHidden)
    }

    func testReadsFinderTagsIntoFileEntries() async throws {
        try "hello".write(to: tempDirectory.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        let service = FileSystemService(
            finderTagService: StubFinderTagService(tagsByLastPathComponent: [
                "note.txt": [FinderTag("Work")]
            ])
        )

        let entries = try await service.contentsOfDirectory(
            at: tempDirectory,
            options: DirectoryReadOptions(showHiddenFiles: false, includeFinderTags: true)
        )
        let entry = try XCTUnwrap(entries.first { $0.name == "note.txt" })

        XCTAssertEqual(entry.finderTags.map(\.name), ["Work"])
    }

    func testSkipsFinderTagReadsWhenFinderTagsAreExcluded() async throws {
        try "hello".write(to: tempDirectory.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        let service = FileSystemService(finderTagService: FailingIfCalledFinderTagService())

        let entries = try await service.contentsOfDirectory(
            at: tempDirectory,
            options: DirectoryReadOptions(showHiddenFiles: false, includeFinderTags: false)
        )
        let entry = try XCTUnwrap(entries.first { $0.name == "note.txt" })

        XCTAssertEqual(entry.finderTags, [])
    }

    func testTreatsFinderTagReadFailureAsEmptyTags() async throws {
        try "hello".write(to: tempDirectory.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        let service = FileSystemService(finderTagService: ThrowingFinderTagService())

        let entries = try await service.contentsOfDirectory(
            at: tempDirectory,
            options: DirectoryReadOptions(showHiddenFiles: false, includeFinderTags: true)
        )
        let entry = try XCTUnwrap(entries.first { $0.name == "note.txt" })

        XCTAssertEqual(entry.finderTags, [])
    }

    func testFolderSymlinkIsDirectoryLike() async throws {
        let target = tempDirectory.appendingPathComponent("Target", isDirectory: true)
        let link = tempDirectory.appendingPathComponent("Target Link")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let service = FileSystemService()
        let entries = try await service.contentsOfDirectory(at: tempDirectory, options: DirectoryReadOptions(showHiddenFiles: false))
        let linkEntry = try XCTUnwrap(entries.first { $0.name == "Target Link" })

        XCTAssertEqual(linkEntry.kind, .symlink)
        XCTAssertTrue(linkEntry.isDirectoryLike)
    }

    func testReadsFolderSymlinkDestination() async throws {
        let target = tempDirectory.appendingPathComponent("Target", isDirectory: true)
        let link = tempDirectory.appendingPathComponent("Target Link")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try "hello".write(to: target.appendingPathComponent("inside.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let service = FileSystemService()
        let entries = try await service.contentsOfDirectory(at: link, options: DirectoryReadOptions(showHiddenFiles: false))

        XCTAssertEqual(entries.map(\.name), ["inside.txt"])
    }

    func testRejectsFileURLWhenDirectoryExpected() async throws {
        let fileURL = tempDirectory.appendingPathComponent("plain.txt")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)

        let service = FileSystemService()

        do {
            _ = try await service.contentsOfDirectory(at: fileURL, options: DirectoryReadOptions())
            XCTFail("Expected notDirectory error")
        } catch {
            XCTAssertEqual(error as? ExplorerError, .notDirectory(fileURL.path))
        }
    }
}

private struct StubFinderTagService: FinderTagServicing {
    var tagsByLastPathComponent: [String: [FinderTag]]

    func tags(for url: URL) throws -> [FinderTag] {
        tagsByLastPathComponent[url.lastPathComponent] ?? []
    }

    func setTags(_ tags: [FinderTag], for url: URL) throws {}
}

private struct ThrowingFinderTagService: FinderTagServicing {
    func tags(for url: URL) throws -> [FinderTag] {
        throw ExplorerError.readFailed("tag read failed")
    }

    func setTags(_ tags: [FinderTag], for url: URL) throws {}
}

private struct FailingIfCalledFinderTagService: FinderTagServicing {
    func tags(for url: URL) throws -> [FinderTag] {
        XCTFail("Finder tags should not be read while listing entries without tag metadata.")
        return []
    }

    func setTags(_ tags: [FinderTag], for url: URL) throws {}
}
