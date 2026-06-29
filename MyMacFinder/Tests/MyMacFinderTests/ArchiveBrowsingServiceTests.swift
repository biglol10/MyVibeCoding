import Foundation
import XCTest
import ZIPFoundation
@testable import MyMacFinder

final class ArchiveBrowsingServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderArchive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testCanOpenOnlyZipFiles() {
        let service = ArchiveBrowsingService()

        XCTAssertTrue(service.canOpen(URL(fileURLWithPath: "/tmp/archive.zip")))
        XCTAssertFalse(service.canOpen(URL(fileURLWithPath: "/tmp/archive.txt")))
    }

    func testListsRootAndNestedFolders() async throws {
        let archiveURL = try makeArchive()
        let service = ArchiveBrowsingService()

        let rootEntries = try await service.list(
            ArchiveLocation(archiveURL: archiveURL, internalPath: ""),
            showHiddenFiles: false
        )
        XCTAssertEqual(rootEntries.map(\.name).sorted(), ["docs", "hidden", "image.png"])
        XCTAssertTrue(rootEntries.first { $0.name == "docs" }?.isDirectory == true)

        let nestedEntries = try await service.list(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "docs"),
            showHiddenFiles: false
        )
        XCTAssertEqual(nestedEntries.map(\.name).sorted(), ["readme.txt"])
        XCTAssertEqual(nestedEntries.first?.size, 5)
    }

    func testFiltersHiddenEntries() async throws {
        let archiveURL = try makeArchive()
        let service = ArchiveBrowsingService()
        let location = ArchiveLocation(archiveURL: archiveURL, internalPath: "hidden")

        let hiddenOff = try await service.list(location, showHiddenFiles: false)
        let hiddenOn = try await service.list(location, showHiddenFiles: true)

        XCTAssertEqual(hiddenOff.map(\.name), [])
        XCTAssertEqual(hiddenOn.map(\.name), [".secret"])
    }

    func testTemporaryExtractReturnsReadableFile() async throws {
        let archiveURL = try makeArchive()
        let service = ArchiveBrowsingService()
        let extracted = try await service.temporaryExtract(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt")
        )

        XCTAssertEqual(try String(contentsOf: extracted, encoding: .utf8), "hello")
    }

    func testInvalidZipThrowsReadableExplorerError() async throws {
        let invalid = tempDirectory.appendingPathComponent("broken.zip")
        try "not a zip".write(to: invalid, atomically: true, encoding: .utf8)
        let service = ArchiveBrowsingService()

        do {
            _ = try await service.list(
                ArchiveLocation(archiveURL: invalid, internalPath: ""),
                showHiddenFiles: false
            )
            XCTFail("Expected invalid archive to throw")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("ZIP"))
        }
    }

    private func makeArchive() throws -> URL {
        let source = tempDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("docs", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("hidden", isDirectory: true), withIntermediateDirectories: true)
        try "hello".write(to: source.appendingPathComponent("docs/readme.txt"), atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source.appendingPathComponent("image.png"))
        try "secret".write(to: source.appendingPathComponent("hidden/.secret"), atomically: true, encoding: .utf8)

        let archiveURL = tempDirectory.appendingPathComponent("fixture.zip")
        try FileManager.default.zipItem(at: source, to: archiveURL, shouldKeepParent: false, compressionMethod: .deflate)
        return archiveURL
    }
}
