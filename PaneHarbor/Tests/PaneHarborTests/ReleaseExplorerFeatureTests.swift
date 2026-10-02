import XCTest
import Foundation
import Darwin
@testable import PaneHarbor

final class ReleaseExplorerFeatureTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PaneHarborFeatures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }
    private func file(_ name: String, _ content: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    private func entries() async throws -> [FileEntry] {
        SortEngine.sorted(try await FileSystemService().contentsOfDirectory(at: root, options: DirectoryReadOptions(showHiddenFiles: true)), descriptor: EntrySortDescriptor())
    }
    func testContentSearchIsBoundedLocalAndRespectsScope() async throws {
        let included = try file("한글 공백.txt", "A secret needle 한글 검색\n")
        let binary = root.appendingPathComponent("binary.dat")
        try Data([0, 110, 101, 101, 100, 108, 101]).write(to: binary)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.txt"), withDestinationURL: included)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try "needle".write(to: nested.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)
        let oversized = root.appendingPathComponent("large.txt")
        try Data(repeating: 65, count: FileSearchService.contentByteLimit + 1).write(to: oversized)
        var options = AdvancedSearchOptions(); options.content = "NEEDLE"
        var criteria = FileEntrySearchCriteria(); criteria.advanced = options; criteria.includeSubfolders = false
        let local = try await FileSearchService().search(in: root, criteria: criteria)
        XCTAssertEqual(local.map(\.name), ["한글 공백.txt"])
        criteria.includeSubfolders = true
        let recursive = try await FileSearchService().search(in: root, criteria: criteria)
        XCTAssertEqual(Set(recursive.map(\.name)), Set(["한글 공백.txt", "deep.txt"]))
        options.content = "한글 검색"; criteria.advanced = options
        let korean = try await FileSearchService().search(in: root, criteria: criteria)
        XCTAssertEqual(korean.map(\.name), ["한글 공백.txt"])
    }
    func testUTF16AndMetadataBoundaryFilters() async throws {
        let url = root.appendingPathComponent("utf16.txt")
        try "테스트 Needle".data(using: .utf16)!.write(to: url)
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        try FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: url.path)
        let list = try await entries(); let entry = try XCTUnwrap(list.first)
        var advanced = AdvancedSearchOptions(); advanced.content = "needle"
        advanced.minimumBytes = entry.size; advanced.maximumBytes = entry.size
        advanced.modifiedFrom = when; advanced.modifiedBefore = when.addingTimeInterval(1)
        var criteria = FileEntrySearchCriteria(); criteria.advanced = advanced
        let found = try await FileSearchService().search(in: root, criteria: criteria)
        XCTAssertEqual(found.count, 1)
        advanced.modifiedBefore = when; criteria.advanced = advanced
        XCTAssertTrue(FileEntrySearchFilter.filtered(list, criteria: criteria).isEmpty)
        advanced.modifiedBefore = nil; advanced.minimumBytes = entry.size! + 1; criteria.advanced = advanced
        XCTAssertTrue(FileEntrySearchFilter.filtered(list, criteria: criteria).isEmpty)
    }
    func testContentSearchExcludesDocumentContainersEvenWhenTheirBytesDecodeAsText() async throws {
        _ = try file("document.pdf", "%PDF-1.7\nneedle\n%%EOF")
        _ = try file("office.docx", "needle")
        _ = try file("renamed-pdf.txt", "%PDF-1.7\nneedle\n%%EOF")
        _ = try file("README", "needle")
        _ = try file("source.swift", "// needle")
        var advanced = AdvancedSearchOptions(); advanced.content = "needle"
        var criteria = FileEntrySearchCriteria(); criteria.advanced = advanced
        let found = try await FileSearchService().search(in: root, criteria: criteria)
        XCTAssertEqual(Set(found.map(\.name)), Set(["README", "source.swift"]))
    }
    func testOldSearchSettingsDecodeAndStoreContentSearchUsesCurrentFolderOnly() async throws {
        let old = Data(#"{"scope":"currentFolder","kind":"any","fileExtension":"","finderTagQuery":""}"#.utf8)
        let decoded = try JSONDecoder().decode(ExplorerSearchOptions.self, from: old)
        XCTAssertNil(decoded.advanced)
        _ = try file("one.txt", "local content needle")
        let nested = root.appendingPathComponent("deep", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try "needle".write(to: nested.appendingPathComponent("two.txt"), atomically: true, encoding: .utf8)
        let root = root!
        let store = await MainActor.run { ExplorerStore(initialURL: root, settingsStore: ReleaseFeatureSettings()) }
        await store.loadInitialDirectory()
        var advanced = AdvancedSearchOptions(); advanced.content = "needle"
        await store.setAdvancedSearch(advanced)
        await store.waitForSearchForTesting()
        let names = await store.activePaneVisibleEntries.map(\.name)
        XCTAssertEqual(names, ["one.txt"])
    }
    func testBatchRenamePreservesExtensionAndContentAndReturnsUndoIdentities() async throws {
        _ = try file("a.txt", "first"); _ = try file("b.txt", "second")
        let list = try await entries()
        var rule = BatchRenameRule(); rule.prefix = "한글 "; rule.suffix = " 사진 "; rule.numbered = true; rule.start = 10
        let plans = try BatchRenameService.plan(entries: list, rule: rule)
        let result = await BatchRenameService().apply(plans)
        XCTAssertNil(result.errorMessage); XCTAssertEqual(result.result.movedItems.count, 2)
        XCTAssertEqual(result.result.undoSourceIdentities.count, 2)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("한글 a 사진 10.txt"), encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("한글 b 사진 11.txt"), encoding: .utf8), "second")
    }
    func testBatchRenameRejectsDuplicateExistingAndTraversalNames() async throws {
        _ = try file("a.txt", "a"); _ = try file("b.txt", "b")
        let list = try await entries()
        var rule = BatchRenameRule(); rule.find = "a"; rule.replacement = "b"
        XCTAssertThrowsError(try BatchRenameService.plan(entries: list, rule: rule))
        rule = BatchRenameRule(); rule.prefix = "../"
        XCTAssertThrowsError(try BatchRenameService.plan(entries: list, rule: rule))
        rule.prefix = "new"; _ = try file("newa.txt", "existing")
        XCTAssertThrowsError(try BatchRenameService.plan(entries: list, rule: rule))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("newa.txt"), encoding: .utf8), "existing")
    }
    func testBatchRenameFailureRollsBackWithoutOverwritingConcurrentTarget() async throws {
        _ = try file("a.txt", "a"); _ = try file("b.txt", "b")
        var rule = BatchRenameRule(); rule.prefix = "new"
        let plans = try BatchRenameService.plan(entries: try await entries(), rule: rule)
        // A target arriving after preview must not be overwritten; the first change must roll back.
        _ = try file("newb.txt", "concurrent")
        let outcome = await BatchRenameService().apply(plans)
        XCTAssertNotNil(outcome.errorMessage); XCTAssertTrue(outcome.result.movedItems.isEmpty)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8), "a")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("b.txt"), encoding: .utf8), "b")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("newb.txt"), encoding: .utf8), "concurrent")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("newa.txt").path))
    }
    func testBatchRenameDetectsChangedSourceAfterPreview() async throws {
        let original = try file("a.txt", "old")
        var rule = BatchRenameRule(); rule.prefix = "new"
        let plans = try BatchRenameService.plan(entries: try await entries(), rule: rule)
        try FileManager.default.moveItem(at: original, to: root.appendingPathComponent("backup.txt"))
        _ = try file("a.txt", "other")
        let outcome = await BatchRenameService().apply(plans)
        XCTAssertNotNil(outcome.errorMessage)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "other")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("newa.txt").path))
    }
    func testSMBAddressRejectsCredentialsAndOtherSchemes() throws {
        XCTAssertEqual(try SMBServerAddress.parse(" server.local/한글 공백 ").host, "server.local")
        XCTAssertEqual(try SMBServerAddress.parse("smb://127.0.0.1:1445/share").port, 1445)
        for text in ["https://server/share", "smb://user:password@server/share", "smb:///share", "smb://server/share?password=bad", "smb://server/share#fragment", "smb://server:0/share"] {
            XCTAssertThrowsError(try SMBServerAddress.parse(text), text)
        }
    }
    @MainActor
    func testBatchRenameStoreUndoRestoresAllOriginalNames() async throws {
        _ = try file("a.txt", "a"); _ = try file("b.txt", "b")
        let store = ExplorerStore(initialURL: root, settingsStore: ReleaseFeatureSettings(), directoryWatcher: nil)
        await store.refresh()
        var rule = BatchRenameRule(); rule.prefix = "renamed "
        let plans = try BatchRenameService.plan(entries: store.activePane.entries, rule: rule)
        await store.applyBatchRename(plans, inPane: store.activePane.id)
        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(Set(store.activeSelectedEntries.map(\.name)), Set(["renamed a.txt", "renamed b.txt"]))
        await store.perform(.undo)
        XCTAssertNil(store.visibleError)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8), "a")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("b.txt"), encoding: .utf8), "b")
    }
    func testControlAndKoreanKeyEventsUseLetterShortcutsAndBackspaceNavigates() {
        XCTAssertEqual(ExplorerKeyCodeMapper.key(for: 0, charactersIgnoringModifiers: "\u{1}"), "a")
        XCTAssertEqual(ExplorerKeyCodeMapper.key(for: 8, charactersIgnoringModifiers: "ㅊ"), "c")
        XCTAssertEqual(ExplorerKeyCodeMapper.key(for: 45, charactersIgnoringModifiers: "\u{e}"), "n")
        XCTAssertEqual(ExplorerKeyCodeMapper.key(for: 51, charactersIgnoringModifiers: "\u{7f}"), "backspace")
        XCTAssertEqual(ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "backspace", modifiers: []), profile: .windows), .goBack)
        XCTAssertEqual(ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "backspace", modifiers: [.command]), profile: .mac), .moveToTrash)
    }
    func testWindowsProfileAndTextEditingRouting() {
        XCTAssertEqual(ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "c", modifiers: [.control]), profile: .windows), .copy)
        XCTAssertEqual(ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "n", modifiers: [.control, .shift]), profile: .windows), .newFolder)
        XCTAssertEqual(ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "f5", modifiers: []), profile: .windows), .refresh)
        XCTAssertEqual(ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "left", modifiers: [.option]), profile: .windows), .goBack)
        XCTAssertNil(ExplorerShortcutRouting.command(for: ExplorerShortcut(key: "delete", modifiers: []), isToolbarTextInputFocused: false, isTextEditingResponderFocused: true, profile: .windows, isCommandEnabled: { _ in true }))
        XCTAssertEqual(ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "f5", modifiers: []), profile: .mac), .copyToOppositePane)
    }
}

private final class ReleaseFeatureSettings: ExplorerSettingsStoring {
    func load() throws -> ExplorerSettings { ExplorerSettings() }
    func save(_ settings: ExplorerSettings) throws {}
}
