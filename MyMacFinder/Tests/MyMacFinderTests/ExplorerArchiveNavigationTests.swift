import Foundation
import XCTest
@testable import MyMacFinder

private final class TestArchiveBrowser: ArchiveBrowsing, @unchecked Sendable {
    var entriesByLocation: [ArchiveLocation: [ArchiveEntry]] = [:]

    func canOpen(_ url: URL) -> Bool {
        url.pathExtension == "zip"
    }

    func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry] {
        entriesByLocation[location] ?? []
    }

    func temporaryExtract(_ location: ArchiveLocation) async throws -> TemporaryArchiveArtifact {
        let ownerDirectoryURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
        return TemporaryArchiveArtifact(
            url: URL(fileURLWithPath: "/tmp/extracted-\(location.nameForTemporaryFile)"),
            ownerDirectoryURL: ownerDirectoryURL,
            ownerIdentifier: UUID(),
            expectedOwnerIdentity: try XCTUnwrap(FileSystemPathIdentity.entryIdentity(ownerDirectoryURL))
        )
    }
}

final class ExplorerArchiveNavigationTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        let root = try XCTUnwrap(tempDirectory)
        try FileManager.default.removeItem(at: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        tempDirectory = nil
    }

    @MainActor
    func testOpeningZipEntersArchiveRoot() async throws {
        let zip = tempDirectory.appendingPathComponent("sample.zip")
        try Data().write(to: zip)
        let archive = TestArchiveBrowser()
        let root = ArchiveLocation(archiveURL: zip, internalPath: "")
        archive.entriesByLocation[root] = [
            ArchiveEntry(location: root.appending("docs"), name: "docs", isDirectory: true, size: nil, modifiedAt: nil)
        ]
        let store = ExplorerStore(initialURL: tempDirectory, archiveBrowser: archive, directoryWatcher: nil)
        await store.loadInitialDirectory()

        await store.open(zip.standardizedFileURL)

        XCTAssertEqual(store.activePane.location, .archive(root))
        XCTAssertEqual(store.pathInput, zip.path + "/")
        XCTAssertEqual(store.activePane.entries.map(\.name), ["docs"])
    }

    @MainActor
    func testOpeningArchiveFolderNavigatesInsideArchive() async throws {
        let zip = tempDirectory.appendingPathComponent("sample.zip")
        try Data().write(to: zip)
        let archive = TestArchiveBrowser()
        let root = ArchiveLocation(archiveURL: zip, internalPath: "")
        let docs = root.appending("docs")
        archive.entriesByLocation[root] = [
            ArchiveEntry(location: docs, name: "docs", isDirectory: true, size: nil, modifiedAt: nil)
        ]
        archive.entriesByLocation[docs] = [
            ArchiveEntry(location: docs.appending("readme.txt"), name: "readme.txt", isDirectory: false, size: 5, modifiedAt: nil)
        ]
        let store = ExplorerStore(initialURL: tempDirectory, archiveBrowser: archive, directoryWatcher: nil)
        await store.loadInitialDirectory()
        await store.open(zip.standardizedFileURL)

        await store.open(store.activePane.entries[0].url)

        XCTAssertEqual(store.activePane.location, .archive(docs))
        XCTAssertEqual(store.activePane.backStack.last, .archive(root))
        XCTAssertEqual(store.activePane.entries.map(\.name), ["readme.txt"])
    }

    @MainActor
    func testGoUpFromArchiveRootReturnsToHostFolder() async throws {
        let zip = tempDirectory.appendingPathComponent("sample.zip")
        try Data().write(to: zip)
        let archive = TestArchiveBrowser()
        archive.entriesByLocation[ArchiveLocation(archiveURL: zip, internalPath: "")] = []
        let store = ExplorerStore(initialURL: tempDirectory, archiveBrowser: archive, directoryWatcher: nil)
        await store.loadInitialDirectory()
        await store.open(zip.standardizedFileURL)

        await store.goUp()

        XCTAssertEqual(store.activePane.location, .fileSystem(tempDirectory.standardizedFileURL))
    }
}

private extension ArchiveLocation {
    var nameForTemporaryFile: String {
        internalPath.replacingOccurrences(of: "/", with: "-")
    }
}
