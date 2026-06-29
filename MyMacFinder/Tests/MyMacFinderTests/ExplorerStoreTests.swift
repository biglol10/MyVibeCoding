import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testNavigateToUpdatesCurrentURLAndBackStack() async throws {
        let child = tempDirectory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: tempDirectory)

        await store.navigate(to: child)

        XCTAssertEqual(store.activePane.currentURL.path, child.path)
        XCTAssertEqual(store.activePane.backStack, [.fileSystem(tempDirectory.standardizedFileURL)])
    }

    @MainActor
    func testOpenCommandNavigatesIntoSelectedFolder() async throws {
        let child = tempDirectory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: tempDirectory)
        await store.refresh()
        store.updateSelection([child.standardizedFileURL])

        await store.perform(.open)

        XCTAssertEqual(store.activePane.currentURL.path, child.path)
    }

    @MainActor
    func testBackAndForwardNavigation() async throws {
        let child = tempDirectory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: tempDirectory)

        await store.navigate(to: child)
        await store.goBack()
        XCTAssertEqual(store.activePane.currentURL.path, tempDirectory.path)
        XCTAssertEqual(store.activePane.forwardStack, [.fileSystem(child.standardizedFileURL)])

        await store.goForward()
        XCTAssertEqual(store.activePane.currentURL.path, child.path)
    }

    @MainActor
    func testBackAndForwardCommandsNavigateHistory() async throws {
        let child = tempDirectory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: tempDirectory)

        XCTAssertFalse(store.canGoBack)
        XCTAssertFalse(store.canGoForward)

        await store.navigate(to: child)
        XCTAssertTrue(store.canGoBack)

        await store.perform(.goBack)
        XCTAssertEqual(store.activePane.currentURL.path, tempDirectory.path)
        XCTAssertFalse(store.canGoBack)
        XCTAssertTrue(store.canGoForward)

        await store.perform(.goForward)
        XCTAssertEqual(store.activePane.currentURL.path, child.path)
        XCTAssertTrue(store.canGoBack)
        XCTAssertFalse(store.canGoForward)
    }

    @MainActor
    func testGoUpCommandIsDisabledAtFilesystemRoot() async {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        let rootStore = ExplorerStore(initialURL: root, directoryWatcher: nil)
        let childStore = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil)

        XCTAssertFalse(rootStore.isCommandEnabled(.goUp))
        XCTAssertTrue(childStore.isCommandEnabled(.goUp))
    }

    @MainActor
    func testGoUpClearsToolbarTextFocus() async throws {
        let child = tempDirectory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: child, directoryWatcher: nil)
        store.setToolbarTextInputFocused(true)

        await store.goUp()

        XCTAssertEqual(store.requestedFocus, .clear)
        XCTAssertFalse(store.isToolbarTextInputFocused)
        XCTAssertEqual(store.pathInput, tempDirectory.path)
    }

    @MainActor
    func testRepeatedGoUpFromFilesystemRootKeepsCanonicalRootPath() async {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        let store = ExplorerStore(initialURL: root, directoryWatcher: nil)
        await store.loadInitialDirectory()

        for _ in 0..<5 {
            await store.goUp()
        }

        XCTAssertEqual(store.activePane.location, .fileSystem(root.standardizedFileURL))
        XCTAssertEqual(store.pathInput, "/")
    }

    @MainActor
    func testSelectAllCommandSelectsVisibleEntriesOnly() async throws {
        let alpha = tempDirectory.appendingPathComponent("Alpha.txt")
        let beta = tempDirectory.appendingPathComponent("Beta.txt")
        try "alpha".write(to: alpha, atomically: true, encoding: .utf8)
        try "beta".write(to: beta, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory)
        await store.refresh()
        store.setSearchQuery("Alpha")

        await store.perform(.selectAll)

        XCTAssertEqual(store.activePane.selectedURLs, [alpha.standardizedFileURL])
    }

    @MainActor
    func testToggleInspectorCommandTogglesInspectorVisibility() async {
        let store = ExplorerStore(initialURL: tempDirectory)
        let initialInspectorVisibility = store.isInspectorVisible

        await store.perform(.toggleInspector)

        XCTAssertEqual(store.isInspectorVisible, !initialInspectorVisibility)
    }

    @MainActor
    func testResolveAndNavigateUsesPathResolver() async throws {
        let child = tempDirectory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: tempDirectory)

        await store.resolveAndNavigate("Child")

        XCTAssertEqual(store.activePane.currentURL.path, child.path)
    }

    @MainActor
    func testInvalidPathSetsVisibleErrorAndKeepsCurrentURL() async {
        let store = ExplorerStore(initialURL: tempDirectory)

        await store.resolveAndNavigate("/definitely/not/here")

        XCTAssertEqual(store.activePane.currentURL.path, tempDirectory.path)
        XCTAssertTrue(store.visibleErrorMessage.contains("Path does not exist"))
    }

    @MainActor
    func testCreateFolderCommandCreatesFolderAndRefreshesEntries() async {
        let store = ExplorerStore(initialURL: tempDirectory)

        await store.perform(.newFolder)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "Untitled Folder" })
    }

    @MainActor
    func testDuplicateCommandDuplicatesSelectedFile() async throws {
        let file = tempDirectory.appendingPathComponent("note.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory)
        await store.refresh()
        store.updateSelection([file.standardizedFileURL])

        await store.perform(.duplicate)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "note copy.txt" })
    }

    @MainActor
    func testRenameSelectedRenamesSingleSelectedFile() async throws {
        let file = tempDirectory.appendingPathComponent("old-name.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory)
        await store.refresh()
        store.updateSelection([file.standardizedFileURL])

        await store.renameSelected(to: "new-name.txt")

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "new-name.txt" })
        XCTAssertFalse(store.activePane.entries.contains { $0.name == "old-name.txt" })
        XCTAssertEqual(store.activePane.selectedEntries.first?.name, "new-name.txt")
    }

    @MainActor
    func testRenameSelectedRejectsPathSeparatorNames() async throws {
        let file = tempDirectory.appendingPathComponent("old-name.txt")
        let nested = tempDirectory.appendingPathComponent("Nested", isDirectory: true)
        try "text".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: tempDirectory)
        await store.refresh()
        store.updateSelection([file.standardizedFileURL])

        await store.renameSelected(to: "Nested/new-name.txt")

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.appendingPathComponent("new-name.txt").path))
        XCTAssertTrue(store.visibleErrorMessage.contains("Invalid path"))
    }

    @MainActor
    func testCopyAndPasteCommandsCopySelectedFileIntoCurrentFolder() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("copy.txt")
        try "copy".write(to: sourceFile, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: sourceFolder)
        await store.refresh()
        store.updateSelection([sourceFile.standardizedFileURL])

        await store.perform(.copy)
        await store.navigate(to: destFolder)
        await store.perform(.paste)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "copy.txt" })
    }

    @MainActor
    func testCopyWithoutSelectionDoesNotEnablePasteOrCopyFiles() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("copy.txt")
        try "copy".write(to: sourceFile, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: sourceFolder)
        await store.refresh()
        store.updateSelection([])

        XCTAssertFalse(store.isCommandEnabled(.copy))

        await store.perform(.copy)

        XCTAssertFalse(store.canPaste)

        await store.navigate(to: destFolder)

        XCTAssertFalse(store.isCommandEnabled(.paste))

        await store.perform(.paste)

        XCTAssertFalse(FileManager.default.fileExists(atPath: destFolder.appendingPathComponent("copy.txt").path))
    }

    @MainActor
    func testPasteWithoutSelectionUsesCurrentFolderWhenClipboardExists() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("copy.txt")
        try "copy".write(to: sourceFile, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: sourceFolder)
        await store.refresh()
        store.updateSelection([sourceFile.standardizedFileURL])

        await store.perform(.copy)
        await store.navigate(to: destFolder)
        store.updateSelection([])

        XCTAssertTrue(store.isCommandEnabled(.paste))

        await store.perform(.paste)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "copy.txt" })
    }

    @MainActor
    func testCutPasteRejectsMovingFolderIntoDescendant() async throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil)
        await store.loadInitialDirectory()
        store.updateSelection([folder.standardizedFileURL])

        await store.perform(.cut)
        await store.navigate(to: child)
        await store.perform(.paste)

        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.path))
        XCTAssertTrue(store.visibleErrorMessage.contains("Cannot move a folder into itself."))
    }

    @MainActor
    func testCopyPasteRejectsCopyingFolderIntoDescendant() async throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil)
        await store.loadInitialDirectory()
        store.updateSelection([folder.standardizedFileURL])

        await store.perform(.copy)
        await store.navigate(to: child)
        await store.perform(.paste)

        XCTAssertFalse(FileManager.default.fileExists(atPath: child.appendingPathComponent("Folder").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(store.visibleErrorMessage.contains("Cannot copy a folder into itself."))
    }

    @MainActor
    func testToolbarTextInputFocusDisablesPasteWithoutSelectionEvenWhenClipboardExists() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("copy.txt")
        try "copy".write(to: sourceFile, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: sourceFolder)
        await store.refresh()
        store.updateSelection([sourceFile.standardizedFileURL])

        await store.perform(.copy)
        await store.navigate(to: destFolder)
        store.updateSelection([])

        XCTAssertTrue(store.isCommandEnabled(.paste))

        store.setToolbarTextInputFocused(true)

        XCTAssertFalse(store.isCommandEnabled(.copy))
        XCTAssertFalse(store.isCommandEnabled(.paste))
    }

    @MainActor
    func testCopyCommandPublishesOperationProgress() async throws {
        let file = tempDirectory.appendingPathComponent("a.txt")
        try "a".write(to: file, atomically: true, encoding: .utf8)
        let destination = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: tempDirectory)
        await store.refresh()
        store.updateSelection([file.standardizedFileURL])
        await store.perform(.copy)
        await store.navigate(to: destination)

        await store.perform(.paste)

        XCTAssertEqual(store.activeOperationProgress?.phase, .completed)
        XCTAssertEqual(store.activeOperationProgress?.kind, .copy)
    }

    @MainActor
    func testToolbarTextInputFocusYieldsEditingShortcutsToTextFields() async throws {
        let file = tempDirectory.appendingPathComponent("note.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory)
        await store.refresh()
        store.updateSelection([file.standardizedFileURL])

        await store.perform(.copy)
        await store.perform(.duplicate)

        XCTAssertTrue(store.isCommandEnabled(.copy))
        XCTAssertTrue(store.isCommandEnabled(.cut))
        XCTAssertTrue(store.isCommandEnabled(.paste))
        XCTAssertTrue(store.isCommandEnabled(.selectAll))
        XCTAssertTrue(store.isCommandEnabled(.undo))
        XCTAssertTrue(store.isCommandEnabled(.newTab))

        store.setToolbarTextInputFocused(true)

        XCTAssertFalse(store.isCommandEnabled(.copy))
        XCTAssertFalse(store.isCommandEnabled(.cut))
        XCTAssertFalse(store.isCommandEnabled(.paste))
        XCTAssertFalse(store.isCommandEnabled(.selectAll))
        XCTAssertFalse(store.isCommandEnabled(.undo))
        XCTAssertTrue(store.isCommandEnabled(.newTab))

        store.setToolbarTextInputFocused(false)

        XCTAssertTrue(store.isCommandEnabled(.copy))
        XCTAssertTrue(store.isCommandEnabled(.paste))
    }

    @MainActor
    func testSelectionChangeClearsToolbarTextInputFocusForFileShortcuts() async throws {
        let file = tempDirectory.appendingPathComponent("note.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory)
        await store.refresh()

        store.setToolbarTextInputFocused(true)

        XCTAssertFalse(store.isCommandEnabled(.copy))

        store.updateSelection([file.standardizedFileURL])

        XCTAssertFalse(store.isToolbarTextInputFocused)
        XCTAssertTrue(store.isCommandEnabled(.copy))
    }

    @MainActor
    func testRepeatedSelectionClearsToolbarTextInputFocusForFileShortcuts() async throws {
        let file = tempDirectory.appendingPathComponent("note.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory)
        await store.refresh()
        store.updateSelection([file.standardizedFileURL])
        store.setToolbarTextInputFocused(true)

        XCTAssertFalse(store.isCommandEnabled(.copy))

        store.updateSelection([file.standardizedFileURL])

        XCTAssertFalse(store.isToolbarTextInputFocused)
        XCTAssertTrue(store.isCommandEnabled(.copy))
    }

    @MainActor
    func testCopyWritesSelectedFilesToSystemPasteboard() async throws {
        let file = tempDirectory.appendingPathComponent("note.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        var writtenURLs: [URL] = []
        let store = ExplorerStore(
            initialURL: tempDirectory,
            filePasteboardWriter: { writtenURLs = $0 }
        )
        await store.refresh()
        store.updateSelection([file.standardizedFileURL])

        await store.perform(.copy)

        XCTAssertEqual(writtenURLs, [file.standardizedFileURL])
    }

    @MainActor
    func testPasteUsesSystemPasteboardFileURLsWhenInternalClipboardIsEmpty() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("external.txt")
        try "external".write(to: sourceFile, atomically: true, encoding: .utf8)
        let store = ExplorerStore(
            initialURL: destFolder,
            filePasteboardReader: { [sourceFile.standardizedFileURL] }
        )

        XCTAssertTrue(store.canPaste)
        XCTAssertTrue(store.isCommandEnabled(.paste))

        await store.perform(.paste)

        let copiedFile = destFolder.appendingPathComponent("external.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedFile.path))
        XCTAssertEqual(store.activeOperationProgress?.kind, .copy)
        XCTAssertEqual(store.activeOperationProgress?.phase, .completed)
    }

    @MainActor
    func testCompletedOperationProgressAutoDismissesAfterDelay() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("copy.txt")
        try "copy".write(to: sourceFile, atomically: true, encoding: .utf8)
        let store = ExplorerStore(
            initialURL: sourceFolder,
            operationProgressAutoDismissNanoseconds: 50_000_000
        )
        await store.refresh()
        store.updateSelection([sourceFile.standardizedFileURL])

        await store.perform(.copy)
        await store.navigate(to: destFolder)
        await store.perform(.paste)

        XCTAssertEqual(store.activeOperationProgress?.phase, .completed)

        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertNil(store.activeOperationProgress)
    }

    @MainActor
    func testFailedOperationProgressDoesNotAutoDismissAfterDelay() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("copy.txt")
        try "copy".write(to: sourceFile, atomically: true, encoding: .utf8)
        let store = ExplorerStore(
            initialURL: sourceFolder,
            operationProgressAutoDismissNanoseconds: 50_000_000
        )
        await store.refresh()
        store.updateSelection([sourceFile.standardizedFileURL])

        await store.perform(.copy)
        try FileManager.default.removeItem(at: sourceFile)
        await store.navigate(to: destFolder)
        await store.perform(.paste)

        XCTAssertEqual(store.activeOperationProgress?.phase, .failed)

        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(store.activeOperationProgress?.phase, .failed)
    }
}
