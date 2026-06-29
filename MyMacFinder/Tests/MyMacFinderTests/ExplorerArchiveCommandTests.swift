import Foundation
import XCTest
@testable import MyMacFinder

private final class ExtractingArchiveBrowser: ArchiveBrowsing, @unchecked Sendable {
    var extractedURL: URL

    init(extractedURL: URL) {
        self.extractedURL = extractedURL
    }

    func canOpen(_ url: URL) -> Bool { url.pathExtension == "zip" }
    func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry] { [] }
    func temporaryExtract(_ location: ArchiveLocation) async throws -> URL { extractedURL }
}

@MainActor
private final class CapturingQuickLookService: QuickLooking {
    var previewedURLs: [URL] = []

    func preview(_ urls: [URL]) throws {
        previewedURLs = urls
    }
}

@MainActor
final class ExplorerArchiveCommandTests: XCTestCase {
    func testMutationCommandsAreDisabledInsideArchive() {
        let archiveURL = URL(fileURLWithPath: "/tmp/sample.zip")
        let location = ArchiveLocation(archiveURL: archiveURL, internalPath: "readme.txt")
        let entry = FileEntry(
            url: location.virtualURL,
            name: "readme.txt",
            kind: .zipVirtualFile,
            typeDescription: "ZIP Item",
            fileExtension: "txt",
            size: 5,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true,
            source: .archive(location)
        )

        XCTAssertFalse(ExplorerCommand.newFolder.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.rename.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.moveToTrash.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.paste.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.cut.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.compressToZip.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.calculateFolderSize.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.editTags.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))

        XCTAssertTrue(ExplorerCommand.open.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertTrue(ExplorerCommand.quickLook.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertTrue(ExplorerCommand.copyPath.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertTrue(ExplorerCommand.revealInFinder.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
    }

    func testQuickLookExtractsArchiveEntryBeforePreviewing() async throws {
        let extracted = URL(fileURLWithPath: "/tmp/extracted-readme.txt")
        let archiveBrowser = ExtractingArchiveBrowser(extractedURL: extracted)
        let quickLook = CapturingQuickLookService()
        let store = ExplorerStore(
            archiveBrowser: archiveBrowser,
            directoryWatcher: nil,
            quickLookService: quickLook
        )
        let archiveLocation = ArchiveLocation(archiveURL: URL(fileURLWithPath: "/tmp/sample.zip"), internalPath: "readme.txt")
        store.replaceActivePaneForTesting(
            location: .archive(archiveLocation.parent),
            entries: [
                FileEntry(
                    url: archiveLocation.virtualURL,
                    name: "readme.txt",
                    kind: .zipVirtualFile,
                    typeDescription: "ZIP Item",
                    fileExtension: "txt",
                    size: 5,
                    dateModified: nil,
                    dateCreated: nil,
                    dateAccessed: nil,
                    isHidden: false,
                    isDirectoryLike: false,
                    isReadable: true,
                    source: .archive(archiveLocation)
                )
            ],
            selectedURLs: [archiveLocation.virtualURL]
        )

        await store.perform(.quickLook)

        XCTAssertEqual(quickLook.previewedURLs, [extracted])
    }
}
