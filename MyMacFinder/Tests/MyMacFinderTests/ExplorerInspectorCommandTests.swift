import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
final class ExplorerInspectorCommandTests: XCTestCase {
    func testQuickLookCommandRequiresSelection() {
        XCTAssertFalse(ExplorerCommand.quickLook.isEnabled(selectionCount: 0, canPaste: false, selectedEntries: []))
        XCTAssertTrue(ExplorerCommand.quickLook.isEnabled(selectionCount: 1, canPaste: false, selectedEntries: [folderEntry()]))
    }

    func testCalculateFolderSizeRequiresSingleFolder() {
        XCTAssertFalse(ExplorerCommand.calculateFolderSize.isEnabled(selectionCount: 0, canPaste: false, selectedEntries: []))
        XCTAssertTrue(ExplorerCommand.calculateFolderSize.isEnabled(selectionCount: 1, canPaste: false, selectedEntries: [folderEntry()]))
        XCTAssertFalse(ExplorerCommand.calculateFolderSize.isEnabled(selectionCount: 1, canPaste: false, selectedEntries: [fileEntry()]))
        XCTAssertFalse(ExplorerCommand.calculateFolderSize.isEnabled(selectionCount: 2, canPaste: false, selectedEntries: [folderEntry(), fileEntry()]))
    }

    func testSpaceMapsToQuickLook() {
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "space", modifiers: [])),
            .quickLook
        )
    }

    func testQuickLookCommandPassesSelectedURLsToService() async {
        let quickLook = SpyQuickLookService()
        let store = ExplorerStore(
            initialURL: URL(fileURLWithPath: "/tmp"),
            fileSystemService: StubFileSystemService(entries: [fileEntry()]),
            settingsStore: InMemoryExplorerSettingsStore(),
            directoryWatcher: nil,
            quickLookService: quickLook
        )
        await store.loadInitialDirectory()
        store.updateSelection([fileEntry().url])

        await store.perform(.quickLook)

        XCTAssertEqual(quickLook.previewedURLs, [fileEntry().url])
    }

    func testCalculateFolderSizeStoresResultForSelectedFolder() async {
        let folder = folderEntry()
        let folderSize = StubFolderSizeService(size: 42)
        let store = ExplorerStore(
            initialURL: URL(fileURLWithPath: "/tmp"),
            fileSystemService: StubFileSystemService(entries: [folder]),
            settingsStore: InMemoryExplorerSettingsStore(),
            directoryWatcher: nil,
            folderSizeService: folderSize
        )
        await store.loadInitialDirectory()
        store.updateSelection([folder.url])

        await store.perform(.calculateFolderSize)

        XCTAssertEqual(store.calculatedFolderSize(for: folder.url), 42)
        XCTAssertEqual(folderSize.requestedURL, folder.url)
    }

    private func folderEntry() -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/tmp/Folder", isDirectory: true),
            name: "Folder",
            kind: .folder,
            typeDescription: "Folder",
            fileExtension: "",
            size: nil,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: true,
            isReadable: true
        )
    }

    private func fileEntry() -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/tmp/file.txt"),
            name: "file.txt",
            kind: .file,
            typeDescription: "Text",
            fileExtension: "txt",
            size: 5,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )
    }
}

private final class StubFolderSizeService: FolderSizeCalculating, @unchecked Sendable {
    var size: Int64
    var requestedURL: URL?

    init(size: Int64) {
        self.size = size
    }

    func size(of folder: URL) throws -> Int64 {
        requestedURL = folder
        return size
    }
}

@MainActor
private final class SpyQuickLookService: QuickLooking {
    var previewedURLs: [URL] = []

    func preview(_ urls: [URL]) throws {
        previewedURLs = urls
    }
}

private struct StubFileSystemService: FileSystemServicing {
    var entries: [FileEntry]

    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry] {
        entries
    }
}

private final class InMemoryExplorerSettingsStore: ExplorerSettingsStoring {
    private var settings = ExplorerSettings()

    func load() -> ExplorerSettings {
        settings
    }

    func save(_ settings: ExplorerSettings) {
        self.settings = settings
    }
}
