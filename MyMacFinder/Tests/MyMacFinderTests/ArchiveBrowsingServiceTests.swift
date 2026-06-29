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

    func testListSkipsUnsafeArchiveEntryPaths() async throws {
        let archiveURL = try makeArchive(
            entries: [
                ("safe.txt", "safe"),
                ("../evil.txt", "evil"),
                ("/absolute.txt", "absolute"),
                ("C:/windows.txt", "windows")
            ]
        )
        let service = ArchiveBrowsingService()

        let entries = try await service.list(
            ArchiveLocation(archiveURL: archiveURL, internalPath: ""),
            showHiddenFiles: true
        )

        XCTAssertEqual(entries.map(\.name), ["safe.txt"])
    }

    func testTemporaryExtractRejectsUnsafeArchiveEntryPaths() async throws {
        let archiveURL = try makeArchive(entries: [("../evil.txt", "evil")])
        let service = ArchiveBrowsingService()

        do {
            _ = try await service.temporaryExtract(
                ArchiveLocation(archiveURL: archiveURL, internalPath: "../evil.txt")
            )
            XCTFail("Expected unsafe archive entry preview to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("outside destination"))
        }
    }

    private func makeArchive() throws -> URL {
        try makeArchive(
            entries: [
                ("docs/readme.txt", "hello"),
                ("image.png", String(decoding: Data([0x89, 0x50, 0x4E, 0x47]), as: UTF8.self)),
                ("hidden/.secret", "secret")
            ]
        )
    }

    private func makeArchive(entries: [(path: String, contents: String)]) throws -> URL {
        let source = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let archiveURL = tempDirectory.appendingPathComponent("fixture.zip")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let archive = try Archive(url: archiveURL, accessMode: .create)
        for entry in entries {
            let data = Data(entry.contents.utf8)
            try archive.addEntry(
                with: entry.path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate,
                bufferSize: max(data.count, 1)
            ) { position, size in
                let start = Int(position)
                let end = min(start + size, data.count)
                return data.subdata(in: start..<end)
            }
        }
        return archiveURL
    }
}
