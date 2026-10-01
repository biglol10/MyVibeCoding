import AppKit
import XCTest
@testable import MyMacFinder

final class ExternalOpenRequestTests: XCTestCase {
    func testURLDecodesExactlyOnceIncludingLiteralPercentPlusAndUnicode() throws {
        let path = "/tmp/한글 공백 %20 + # & ?.txt"
        var components = URLComponents()
        components.scheme = "mymacfinder"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        XCTAssertEqual(try ExternalOpenRequest.fileURL(from: XCTUnwrap(components.url)).path, path)
        // This is the exact encoding produced by JavaScript encodeURIComponent.
        let jsURL = try XCTUnwrap(URL(string: "mymacfinder://open?path=%2Ftmp%2F%ED%95%9C%EA%B8%80%20%EA%B3%B5%EB%B0%B1%20%2520%20%2B%20%23%20%26%20%3F.txt"))
        XCTAssertEqual(try ExternalOpenRequest.fileURL(from: jsURL).path, path)
    }

    func testRejectsRemoteURLsCommandsRelativeAndAmbiguousRequests() throws {
        for value in ["https://example.com/test", "file://server/tmp/a", "mymacfinder://open?path=relative", "mymacfinder://open?path=/tmp/a&path=/tmp/b", "mymacfinder://other?path=/tmp/a", "mymacfinder://open?path=/tmp/a#fragment", "mymacfinder://open?path=/tmp/%00a"] {
            XCTAssertThrowsError(try ExternalOpenRequest.fileURL(from: XCTUnwrap(URL(string: value))), value)
        }
        XCTAssertThrowsError(try ExternalOpenRequest.fileURL(fromPathText: "code ."))
        XCTAssertThrowsError(try ExternalOpenRequest.fileURL(fromPathText: "relative.txt"))
    }

    @MainActor
    func testServiceReadsFileURLsLegacyFilesAndPathTextWithoutChangingPasteboard() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let url = URL(fileURLWithPath: "/tmp/한글 공백.txt")
        board.writeObjects([url as NSURL])
        XCTAssertEqual(try ExternalOpenRequest.fileURLs(from: board), [url])
        board.clearContents()
        board.setPropertyList([url.path], forType: .init("NSFilenamesPboardType"))
        XCTAssertEqual(try ExternalOpenRequest.fileURLs(from: board), [url])
        board.clearContents()
        board.setString(url.path, forType: .string)
        let count = board.changeCount
        XCTAssertEqual(try ExternalOpenRequest.fileURLs(from: board), [url])
        XCTAssertEqual(board.changeCount, count)
        board.setString("https://example.com", forType: .string)
        XCTAssertThrowsError(try ExternalOpenRequest.fileURLs(from: board))
    }

    @MainActor
    func testRevealFolderThenFileWithFiltersAndMissingPathKeepsCurrentLocation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("폴더 공백", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("선택 파일 + %.txt")
        try "fixture".write(to: file, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: root, directoryWatcher: nil)
        await store.loadInitialDirectory()
        await store.openExternalURL(folder)
        XCTAssertEqual(store.activePane.currentURL, folder)
        XCTAssertTrue(store.activePane.selectedURLs.isEmpty)
        store.setSearchQuery("unmatched filter")
        store.setSearchKindFilter(.folders)
        await store.openExternalURL(file)
        XCTAssertEqual(store.activePane.currentURL, folder)
        XCTAssertEqual(store.activeSelectedEntries.map(\.url), [file])
        XCTAssertEqual(store.searchQuery, "")
        XCTAssertNil(store.visibleError)
        let missing = folder.appendingPathComponent("존재하지 않음.txt")
        await store.openExternalURL(missing)
        XCTAssertEqual(store.visibleError, .pathDoesNotExist(missing.path))
        XCTAssertEqual(store.activePane.currentURL, folder)
        XCTAssertEqual(store.activePane.selectedURLs, [file])
        await store.openExternalURL(folder)
        XCTAssertNil(store.visibleError)
    }

    @MainActor
    func testExternalZIPIsSelectedAndHiddenFileBecomesVisible() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExplorerStore(initialURL: root, directoryWatcher: nil)
        for name in ["archive.zip", ".hidden 한글.txt"] {
            let file = root.appendingPathComponent(name)
            try Data().write(to: file)
            await store.openExternalURL(file)
            XCTAssertEqual(store.activePane.location, .fileSystem(root))
            XCTAssertEqual(store.activeSelectedEntries.map(\.url), [file])
        }
        XCTAssertTrue(store.showHiddenFiles)
    }
}
