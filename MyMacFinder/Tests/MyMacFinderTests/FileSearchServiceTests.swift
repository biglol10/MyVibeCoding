import Foundation
import XCTest
@testable import MyMacFinder

final class FileSearchServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderFileSearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try FileManager.default.removeItem(at: tempDirectory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
        }
    }

    func testRecursiveSearchFindsNestedEntriesAndSkipsHiddenWhenDisabled() async throws {
        let nested = tempDirectory.appendingPathComponent("Nested", isDirectory: true)
        let hidden = tempDirectory.appendingPathComponent(".Hidden", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try "top".write(to: tempDirectory.appendingPathComponent("TopReport.txt"), atomically: true, encoding: .utf8)
        try "deep".write(to: nested.appendingPathComponent("DeepReport.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: hidden.appendingPathComponent("HiddenReport.txt"), atomically: true, encoding: .utf8)

        let results = try await FileSearchService().search(
            in: tempDirectory,
            criteria: FileEntrySearchCriteria(query: "report", kind: .files),
            options: DirectoryReadOptions(showHiddenFiles: false)
        )

        XCTAssertEqual(results.map(\.name), ["DeepReport.txt", "TopReport.txt"])
    }

    func testRecursiveSearchCanFilterFolders() async throws {
        let reportFolder = tempDirectory.appendingPathComponent("Report Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: reportFolder, withIntermediateDirectories: true)
        try "report".write(to: tempDirectory.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)

        let results = try await FileSearchService().search(
            in: tempDirectory,
            criteria: FileEntrySearchCriteria(query: "report", kind: .folders),
            options: DirectoryReadOptions(showHiddenFiles: true)
        )

        XCTAssertEqual(results.map(\.name), ["Report Folder"])
    }

    func testRecursiveSearchMatchesDirectorySymlinkWithoutTraversingItsTarget() async throws {
        let root = tempDirectory.appendingPathComponent("Root", isDirectory: true)
        let outside = tempDirectory.appendingPathComponent("Outside", isDirectory: true)
        let link = root.appendingPathComponent("Report Link")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "outside".write(
            to: outside.appendingPathComponent("OutsideReport.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let results = try await FileSearchService().search(
            in: root,
            criteria: FileEntrySearchCriteria(query: "report"),
            options: DirectoryReadOptions(showHiddenFiles: true)
        )

        XCTAssertEqual(results.map(\.name), ["Report Link"])
    }

    func testRecursiveSearchSkipsPermissionDeniedDescendantAndContinues() async throws {
        let root = tempDirectory.appendingPathComponent("Root", isDirectory: true).standardizedFileURL
        let denied = root.appendingPathComponent("Denied", isDirectory: true).standardizedFileURL
        let readable = root.appendingPathComponent("Readable", isDirectory: true).standardizedFileURL
        let report = readable.appendingPathComponent("ReadableReport.txt").standardizedFileURL
        let fileSystem = ScriptedSearchFileSystemService(responses: [
            root: .entries([
                makeEntry(url: denied, kind: .folder, isDirectoryLike: true),
                makeEntry(url: readable, kind: .folder, isDirectoryLike: true)
            ]),
            denied: .explorerError(.permissionDenied(denied.path)),
            readable: .entries([makeEntry(url: report, kind: .file)])
        ])

        let results = try await FileSearchService(fileSystemService: fileSystem).search(
            in: root,
            criteria: FileEntrySearchCriteria(query: "report"),
            options: DirectoryReadOptions()
        )

        XCTAssertEqual(results.map(\.url), [report])
        let requestedURLs = await fileSystem.requestedURLs
        XCTAssertEqual(Set(requestedURLs), Set([root, denied, readable]))
    }

    func testRecursiveSearchThrowsPermissionDeniedForRoot() async throws {
        let root = tempDirectory.appendingPathComponent("DeniedRoot", isDirectory: true).standardizedFileURL
        let fileSystem = ScriptedSearchFileSystemService(responses: [
            root: .explorerError(.permissionDenied(root.path))
        ])

        do {
            _ = try await FileSearchService(fileSystemService: fileSystem).search(
                in: root,
                criteria: FileEntrySearchCriteria(query: "report"),
                options: DirectoryReadOptions()
            )
            XCTFail("Expected root permission error")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .permissionDenied(root.path))
        }
    }

    func testRecursiveSearchDoesNotTraverseUnreadableDirectoryEntry() async throws {
        let root = tempDirectory.appendingPathComponent("Root", isDirectory: true).standardizedFileURL
        let unreadable = root.appendingPathComponent("Unreadable", isDirectory: true).standardizedFileURL
        let fileSystem = ScriptedSearchFileSystemService(responses: [
            root: .entries([
                makeEntry(url: unreadable, kind: .folder, isDirectoryLike: true, isReadable: false)
            ])
        ])

        let results = try await FileSearchService(fileSystemService: fileSystem).search(
            in: root,
            criteria: FileEntrySearchCriteria(query: "report"),
            options: DirectoryReadOptions()
        )

        XCTAssertTrue(results.isEmpty)
        let requestedURLs = await fileSystem.requestedURLs
        XCTAssertEqual(requestedURLs, [root])
    }

    func testRecursiveSearchPropagatesCancellation() async throws {
        let root = tempDirectory.appendingPathComponent("Root", isDirectory: true).standardizedFileURL
        let fileSystem = ScriptedSearchFileSystemService(responses: [root: .cancelled])

        do {
            _ = try await FileSearchService(fileSystemService: fileSystem).search(
                in: root,
                criteria: FileEntrySearchCriteria(query: "report"),
                options: DirectoryReadOptions()
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            let requestedURLs = await fileSystem.requestedURLs
            XCTAssertEqual(requestedURLs, [root])
        }
    }

    func testRecursiveSearchPropagatesCancellationWhenDirectoryReadIgnoresCancellation() async throws {
        let root = tempDirectory.appendingPathComponent("NonCooperativeRoot", isDirectory: true).standardizedFileURL
        let match = makeEntry(
            url: root.appendingPathComponent("LateReport.txt"),
            kind: .file
        )
        let fileSystem = NonCooperativeSearchFileSystemService()
        let task = Task {
            try await FileSearchService(fileSystemService: fileSystem).search(
                in: root,
                criteria: FileEntrySearchCriteria(query: "report"),
                options: DirectoryReadOptions()
            )
        }
        await fileSystem.waitUntilReadStarts()

        task.cancel()
        await fileSystem.resume(with: [match])

        do {
            _ = try await task.value
            XCTFail("Expected cancellation after a non-cooperative directory read")
        } catch is CancellationError {
            // Expected.
        }
    }

    private func makeEntry(
        url: URL,
        kind: FileEntryKind,
        isDirectoryLike: Bool = false,
        isReadable: Bool = true
    ) -> FileEntry {
        FileEntry(
            url: url,
            name: url.lastPathComponent,
            kind: kind,
            typeDescription: kind == .folder ? "Folder" : "File",
            fileExtension: url.pathExtension,
            size: nil,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: isDirectoryLike,
            isReadable: isReadable
        )
    }
}

private enum ScriptedSearchDirectoryResponse: Sendable {
    case entries([FileEntry])
    case explorerError(ExplorerError)
    case cancelled
}

private actor ScriptedSearchFileSystemService: FileSystemServicing {
    private let responses: [URL: ScriptedSearchDirectoryResponse]
    private(set) var requestedURLs: [URL] = []

    init(responses: [URL: ScriptedSearchDirectoryResponse]) {
        self.responses = responses
    }

    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry] {
        let url = url.standardizedFileURL
        requestedURLs.append(url)
        guard let response = responses[url] else {
            throw ExplorerError.readFailed("Unexpected directory read: \(url.path)")
        }
        switch response {
        case .entries(let entries):
            return entries
        case .explorerError(let error):
            throw error
        case .cancelled:
            throw CancellationError()
        }
    }
}

private actor NonCooperativeSearchFileSystemService: FileSystemServicing {
    private var readContinuation: CheckedContinuation<[FileEntry], Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var didStart = false

    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry] {
        didStart = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { continuation in
            readContinuation = continuation
        }
    }

    func waitUntilReadStarts() async {
        if didStart {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiter = continuation
        }
    }

    func resume(with entries: [FileEntry]) {
        readContinuation?.resume(returning: entries)
        readContinuation = nil
    }
}
