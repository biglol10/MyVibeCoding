import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
final class ExplorerFinderTagCommandTests: XCTestCase {
    func testEditTagsCommandWritesPromptedTagsAndRefreshesSelection() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let fileURL = tempDirectory.appendingPathComponent("tagged.txt").standardizedFileURL
        try "tagged".write(to: fileURL, atomically: true, encoding: .utf8)
        let tagService = CapturingFinderTagService()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            fileSystemService: FileSystemService(finderTagService: tagService),
            settingsStore: InMemoryFinderTagCommandSettingsStore(),
            directoryWatcher: nil,
            finderTagService: tagService,
            finderTagPrompt: { entry in
                XCTAssertEqual(entry.name, "tagged.txt")
                return [FinderTag("Work"), FinderTag("Red")]
            }
        )
        await store.loadInitialDirectory()
        store.updateSelection([fileURL])

        await store.perform(.editTags)

        XCTAssertEqual(tagService.writtenTagsByURL[fileURL]?.map(\.name), ["Red", "Work"])
        XCTAssertEqual(store.activePane.selectedURLs, [fileURL])
        XCTAssertEqual(store.activeSelectedEntries.first?.finderTags.map(\.name), ["Red", "Work"])
    }

    func testEditTagsCommandDoesNothingWhenPromptIsCancelled() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let fileURL = tempDirectory.appendingPathComponent("tagged.txt").standardizedFileURL
        try "tagged".write(to: fileURL, atomically: true, encoding: .utf8)
        let tagService = CapturingFinderTagService()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            fileSystemService: FileSystemService(finderTagService: tagService),
            settingsStore: InMemoryFinderTagCommandSettingsStore(),
            directoryWatcher: nil,
            finderTagService: tagService,
            finderTagPrompt: { _ in nil }
        )
        await store.loadInitialDirectory()
        store.updateSelection([fileURL])

        await store.perform(.editTags)

        XCTAssertEqual(tagService.writtenTagsByURL, [:])
        XCTAssertEqual(store.activePane.selectedURLs, [fileURL])
    }

    func testEditTagsClearsSelectionWhenEditedTagsNoLongerMatchActiveTagFilter() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let fileURL = tempDirectory.appendingPathComponent("tagged.txt").standardizedFileURL
        try "tagged".write(to: fileURL, atomically: true, encoding: .utf8)
        let tagService = CapturingFinderTagService()
        tagService.writtenTagsByURL[fileURL] = [FinderTag("Work")]
        let store = ExplorerStore(
            initialURL: tempDirectory,
            fileSystemService: FileSystemService(finderTagService: tagService),
            settingsStore: InMemoryFinderTagCommandSettingsStore(),
            directoryWatcher: nil,
            finderTagService: tagService,
            finderTagPrompt: { entry in
                XCTAssertEqual(entry.finderTags.map(\.name), ["Work"])
                return [FinderTag("Personal")]
            }
        )
        await store.loadInitialDirectory()
        store.setSearchFinderTagQuery("work")
        store.updateSelection([fileURL])

        await store.perform(.editTags)

        XCTAssertEqual(tagService.writtenTagsByURL[fileURL]?.map(\.name), ["Personal"])
        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), [])
        XCTAssertEqual(store.activePane.selectedURLs, [])
        XCTAssertEqual(store.activeSelectedEntries, [])
    }

    func testEditTagsReadsAndWritesFinderTagsOffMainThread() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let fileURL = tempDirectory.appendingPathComponent("tagged.txt").standardizedFileURL
        try "tagged".write(to: fileURL, atomically: true, encoding: .utf8)
        let tagService = ThreadRecordingFinderTagService(tagsByURL: [
            fileURL: [FinderTag("Work")]
        ])
        let store = ExplorerStore(
            initialURL: tempDirectory,
            fileSystemService: FileSystemService(finderTagService: tagService),
            settingsStore: InMemoryFinderTagCommandSettingsStore(),
            directoryWatcher: nil,
            finderTagService: tagService,
            finderTagPrompt: { entry in
                XCTAssertEqual(entry.finderTags.map(\.name), ["Work"])
                return [FinderTag("Personal")]
            }
        )
        await store.loadInitialDirectory()
        store.updateSelection([fileURL])

        await store.perform(.editTags)

        XCTAssertEqual(tagService.readMainThreadFlags(), [false])
        XCTAssertEqual(tagService.writeMainThreadFlags(), [false])
        XCTAssertEqual(tagService.tagsByURLSnapshot()[fileURL]?.map(\.name), ["Personal"])
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderExplorerFinderTagCommand-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class CapturingFinderTagService: FinderTagServicing, @unchecked Sendable {
    var writtenTagsByURL: [URL: [FinderTag]] = [:]

    func tags(for url: URL) throws -> [FinderTag] {
        writtenTagsByURL[url.standardizedFileURL] ?? []
    }

    func setTags(_ tags: [FinderTag], for url: URL) throws {
        writtenTagsByURL[url.standardizedFileURL] = FinderTag.normalized(tags.map(\.name))
    }
}

private final class ThreadRecordingFinderTagService: FinderTagServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var tagsByURL: [URL: [FinderTag]]
    private var readFlags: [Bool] = []
    private var writeFlags: [Bool] = []

    init(tagsByURL: [URL: [FinderTag]]) {
        self.tagsByURL = tagsByURL.reduce(into: [:]) { result, pair in
            result[pair.key.standardizedFileURL] = pair.value
        }
    }

    func tags(for url: URL) throws -> [FinderTag] {
        lock.lock()
        defer { lock.unlock() }
        readFlags.append(Thread.isMainThread)
        return tagsByURL[url.standardizedFileURL] ?? []
    }

    func setTags(_ tags: [FinderTag], for url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        writeFlags.append(Thread.isMainThread)
        tagsByURL[url.standardizedFileURL] = FinderTag.normalized(tags.map(\.name))
    }

    func readMainThreadFlags() -> [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return readFlags
    }

    func writeMainThreadFlags() -> [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return writeFlags
    }

    func tagsByURLSnapshot() -> [URL: [FinderTag]] {
        lock.lock()
        defer { lock.unlock() }
        return tagsByURL
    }
}

private final class InMemoryFinderTagCommandSettingsStore: ExplorerSettingsStoring {
    private var settings = ExplorerSettings()

    func load() -> ExplorerSettings {
        settings
    }

    func save(_ settings: ExplorerSettings) {
        self.settings = settings
    }
}
