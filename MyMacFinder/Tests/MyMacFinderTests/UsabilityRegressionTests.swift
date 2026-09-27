import Foundation
import ZIPFoundation
import XCTest
@testable import MyMacFinder

final class UsabilityRegressionTests: XCTestCase {
    @MainActor func testCopyingSameURLsAgainMustInvalidateCutMode() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("a.txt"), destination = root.appendingPathComponent("destination")
        try Data([1]).write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var clipboard: [URL] = []
        var changeCount = 0
        let s = store(root, reader: { clipboard }, writer: { clipboard = $0; changeCount += 1 }, changeCount: { changeCount })
        await s.refresh(); s.updateSelection([source]); await s.perform(.cut)
        changeCount += 1 // Another app copies the same file, changing ownership but not URLs.
        await s.navigate(to: destination); await s.perform(.paste)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("a.txt")), Data([1]))
    }

    @MainActor func testUnchangedCutClipboardStillMoves() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("a.txt"), destination = root.appendingPathComponent("destination")
        try Data([1]).write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var clipboard: [URL] = []
        let s = store(root, reader: { clipboard }, writer: { clipboard = $0 })
        await s.refresh(); s.updateSelection([source]); await s.perform(.cut)
        await s.navigate(to: destination); await s.perform(.paste)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("a.txt")), Data([1]))
    }

    @MainActor func testClearedSystemClipboardCannotPasteOldCut() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("a.txt")
        try Data([1]).write(to: source)
        var clipboard: [URL] = []
        let s = store(root, reader: { clipboard }, writer: { clipboard = $0 })
        await s.refresh(); s.updateSelection([source]); await s.perform(.cut)
        clipboard = []
        XCTAssertFalse(s.canPaste)
        await s.perform(.paste)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["a.txt"])
    }

    @MainActor func testMissingSearchSelectionIsRemovedAfterTabRestore() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("match.txt")
        try Data([1]).write(to: file)
        let s = store(root); await s.refresh(); s.setSearchScope(.recursive); s.setSearchQuery("match")
        try await finishSearch(s); s.updateSelection([file]); await s.newTab()
        try FileManager.default.removeItem(at: file)
        await s.selectTab(at: 0); try await finishSearch(s)
        XCTAssertTrue(s.activePane.selectedURLs.isEmpty)
        XCTAssertFalse(s.isCommandEnabled(.rename))
    }

    @MainActor func testClearAllFiltersRestoresOrdinaryFolderContents() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("a.txt"))
        let s = store(root); await s.refresh()
        s.setSearchScope(.recursive); s.setSearchKindFilter(.folders)
        s.setSearchFileExtension("pdf"); s.setSearchFinderTagQuery("missing"); s.setSearchQuery("none")
        try await finishSearch(s); XCTAssertTrue(s.activePaneVisibleEntries.isEmpty)
        s.clearAllSearchCriteria()
        XCTAssertFalse(s.hasActiveSearchCriteria)
        XCTAssertEqual(s.searchOptions, ExplorerSearchOptions())
        XCTAssertFalse(s.isSearching)
        XCTAssertEqual(s.activePaneVisibleEntries.map(\.name), ["a.txt"])
    }

    @MainActor func testArchiveFolderRejectsSizeCalculationWithoutError() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data([1]).write(to: folder.appendingPathComponent("file.txt"))
        let zipURL = root.appendingPathComponent("sample.zip")
        try FileManager.default.zipItem(at: folder, to: zipURL)
        let s = store(root); await s.refresh(); await s.open(zipURL)
        let entry = try XCTUnwrap(s.activePane.entries.first)
        s.updateSelection([entry.url])
        XCTAssertFalse(s.isCommandEnabled(.calculateFolderSize))
        await s.perform(.calculateFolderSize)
        XCTAssertNil(s.visibleError)
        XCTAssertTrue(s.calculatedFolderSizes.isEmpty)
        XCTAssertEqual(InspectorItemDetails(entry: entry).path, zipURL.path + "/folder")
    }

    @MainActor func testRefreshDiscardsInFlightFolderSizeResult() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let calculator = PausedFolderSizeCalculator()
        let s = store(root, folderSizeService: calculator)
        await s.refresh(); s.updateSelection([try XCTUnwrap(s.activePane.entries.first).url])
        let calculation = Task { await s.perform(.calculateFolderSize) }
        defer { calculator.resume.signal() }
        for _ in 0..<300 {
            if calculator.hasStarted { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(calculator.hasStarted)
        await s.refresh()
        calculator.resume.signal()
        await calculation.value
        XCTAssertTrue(s.calculatedFolderSizes.isEmpty)
    }

    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FinderAuditProbe-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor private func store(_ root: URL, operation: FileOperationService = FileOperationService(), reader: @escaping FilePasteboardReader = { [] }, writer: @escaping FilePasteboardWriter = { _ in }, changeCount: @escaping FilePasteboardChangeCount = { 0 }, folderSizeService: any FolderSizeCalculating = FolderSizeService()) -> ExplorerStore {
        let domain = "FinderAuditProbe.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        addTeardownBlock { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
        return ExplorerStore(initialURL: root, fileOperationService: operation,
            settingsStore: UserDefaultsExplorerSettingsStore(defaults: defaults),
            sidebarFavoritesStore: UserDefaultsSidebarFavoritesStore(defaults: defaults),
            directoryWatcher: nil, bookmarkStore: SecurityScopedBookmarkStore(defaults: defaults),
            folderSizeService: folderSizeService, quickLookService: nil, filePasteboardReader: reader, filePasteboardWriter: writer, filePasteboardChangeCount: changeCount)
    }

    @MainActor private func finishSearch(_ store: ExplorerStore) async throws {
        for _ in 0..<300 {
            if !store.isSearching { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Search timeout")
    }

    @MainActor func testExternalClipboardMustOverrideEarlierCut() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.txt"), b = root.appendingPathComponent("b.txt"), dest = root.appendingPathComponent("destination")
        try Data([1]).write(to: a); try Data([2]).write(to: b)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
        var clipboard: [URL] = []
        let s = store(root, reader: { clipboard }, writer: { clipboard = $0 })
        await s.refresh(); s.updateSelection([a]); await s.perform(.cut)
        clipboard = [b]
        await s.navigate(to: dest); await s.perform(.paste)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path), "Earlier cut source must remain after another app copies b")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("b.txt").path), "Paste must use new system clipboard")
    }

    func testFolderSizeMustIncludeHiddenContents() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0, count: 10).write(to: root.appendingPathComponent("visible"))
        try Data(repeating: 0, count: 90).write(to: root.appendingPathComponent(".hidden"))
        XCTAssertEqual(try FolderSizeService().size(of: root), 100)
    }

    @MainActor func testCalculatedFolderSizeMustInvalidateAfterRefresh() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder"), file = folder.appendingPathComponent("visible")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data(repeating: 0, count: 10).write(to: file)
        let s = store(root); await s.refresh(); let selected = try XCTUnwrap(s.activePane.entries.first(where: { $0.name == "folder" })?.url); s.updateSelection([selected]); await s.perform(.calculateFolderSize)
        XCTAssertEqual(s.calculatedFolderSize(for: selected), 10)
        try Data(repeating: 0, count: 100).write(to: file)
        await s.refresh()
        XCTAssertNotEqual(s.calculatedFolderSize(for: selected), 10, "Refresh must not keep obsolete calculated size")
    }

    @MainActor func testRenameNestedRecursiveResultMustWork() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("sub"), file = folder.appendingPathComponent("match.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data([1]).write(to: file)
        let s = store(root); await s.refresh(); s.setSearchScope(.recursive); s.setSearchQuery("match")
        try await finishSearch(s); XCTAssertEqual(s.activePaneVisibleEntries.map(\.name), ["match.txt"])
        s.updateSelection([file]); XCTAssertTrue(s.isCommandEnabled(.rename)); await s.renameSelected(to: "match-renamed.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("match-renamed.txt").path), "Enabled rename must rename nested search result")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try await finishSearch(s)
        XCTAssertEqual(s.activePaneVisibleEntries.map(\.name), ["match-renamed.txt"])
        XCTAssertEqual(s.activeSelectedEntries.map(\.name), ["match-renamed.txt"])
    }

    @MainActor func testRecursiveSelectionMustSurviveTabRoundTrip() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("sub"), file = folder.appendingPathComponent("match.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data([1]).write(to: file)
        let s = store(root); await s.refresh(); s.setSearchScope(.recursive); s.setSearchQuery("match")
        try await finishSearch(s); s.updateSelection([file]); await s.newTab(); await s.selectTab(at: 0)
        try await finishSearch(s)
        XCTAssertEqual(s.activePane.selectedURLs, [file], "Tab switch should preserve selected search result")
    }

    @MainActor func testFailedBatchDuplicateMustRollbackOrRetainUndo() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.txt"), b = root.appendingPathComponent("b.txt")
        try Data([1]).write(to: a); try Data([2]).write(to: b)
        let operation = FileOperationService(moveItemAction: { source, destination in
            if destination.lastPathComponent.hasPrefix("b copy") { throw ExplorerError.operationFailed("Injected second-item failure") }
            try FileManager.default.moveItem(at: source, to: destination)
        })
        let s = store(root, operation: operation); await s.refresh(); s.updateSelection([a,b]); await s.perform(.duplicate)
        XCTAssertNotNil(s.visibleError)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.contains("copy") }
        XCTAssertTrue(leftovers.isEmpty, "Failed batch must roll back all copies: \(leftovers)")
        XCTAssertFalse(s.canUndo)
        XCTAssertEqual(try Data(contentsOf: a), Data([1]))
        XCTAssertEqual(try Data(contentsOf: b), Data([2]))
    }

    func testInspectorDateMustAgreeWithLocalTableDate() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm"
        XCTAssertEqual(InspectorItemDetails.dateText(date), formatter.string(from: date))
    }
}

private final class PausedFolderSizeCalculator: FolderSizeCalculating, @unchecked Sendable {
    let resume = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var started = false
    var hasStarted: Bool { lock.withLock { started } }
    func size(of folder: URL) throws -> Int64 {
        lock.withLock { started = true }
        guard resume.wait(timeout: .now() + 5) == .success else {
            throw ExplorerError.operationFailed("Test calculation timed out")
        }
        return 10
    }
}
