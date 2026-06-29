import Foundation
import XCTest
@testable import MyMacFinder

final class FilePreviewContentLoaderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderPreviewContent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testLoadsUTF8TextPreviewForMarkdownFile() async throws {
        let file = tempDirectory.appendingPathComponent("notes.md")
        try "# Notes\nPreview text".write(to: file, atomically: true, encoding: .utf8)

        let content = await FilePreviewContentLoader.loadContent(for: makeEntry(url: file, extension: "md"))

        guard case .text(let preview) = content else {
            return XCTFail("Expected text preview, got \(content)")
        }
        XCTAssertEqual(preview.text, "# Notes\nPreview text")
        XCTAssertFalse(preview.isTruncated)
        XCTAssertEqual(preview.encodingName, "UTF-8")
    }

    func testLargeTextPreviewIsByteLimitedAndMarkedTruncated() async throws {
        let file = tempDirectory.appendingPathComponent("server.log")
        try String(repeating: "abcdef", count: 20).write(to: file, atomically: true, encoding: .utf8)

        let content = await FilePreviewContentLoader.loadContent(
            for: makeEntry(url: file, extension: "log"),
            byteLimit: 24
        )

        guard case .text(let preview) = content else {
            return XCTFail("Expected text preview, got \(content)")
        }
        XCTAssertEqual(preview.text, String(repeating: "abcdef", count: 4))
        XCTAssertTrue(preview.isTruncated)
        XCTAssertEqual(preview.byteLimit, 24)
    }

    @MainActor
    func testFileReadRunsOffMainThreadWhenCalledFromMainActor() async throws {
        let file = tempDirectory.appendingPathComponent("notes.md")
        let observation = ThreadObservation()

        let content = await FilePreviewContentLoader.loadContent(
            for: makeEntry(url: file, extension: "md"),
            fileReader: { _, _ in
                observation.record(isMainThread: Thread.isMainThread)
                return FilePreviewReadResult(data: Data("# Notes".utf8), fileSize: 7)
            }
        )

        guard case .text(let preview) = content else {
            return XCTFail("Expected text preview, got \(content)")
        }
        XCTAssertEqual(preview.text, "# Notes")
        XCTAssertEqual(observation.values, [false])
    }

    func testDefaultPreviewKeepsTextSmallEnoughForResponsiveInspectorRendering() async throws {
        let file = tempDirectory.appendingPathComponent("large.log")
        try String(repeating: "0123456789abcdef\n", count: 8_000).write(to: file, atomically: true, encoding: .utf8)

        let content = await FilePreviewContentLoader.loadContent(for: makeEntry(url: file, extension: "log"))

        guard case .text(let preview) = content else {
            return XCTFail("Expected text preview, got \(content)")
        }
        XCTAssertEqual(preview.byteLimit, 16 * 1024)
        XCTAssertLessThanOrEqual(preview.text.utf8.count, 16 * 1024)
        XCTAssertTrue(preview.isTruncated)
    }

    func testCancellationPropagatesToBackgroundTextReadTask() async throws {
        let file = tempDirectory.appendingPathComponent("slow.log")
        try "slow preview".write(to: file, atomically: true, encoding: .utf8)
        let probe = CancellationProbe()
        let entry = makeEntry(url: file, extension: "log")

        let task = Task {
            await FilePreviewContentLoader.loadContent(
                for: entry,
                fileReader: { _, _ in
                    probe.recordStarted()
                    while !Task.isCancelled, !probe.hasTimedOut {
                        Thread.sleep(forTimeInterval: 0.005)
                    }
                    probe.recordCancellation(isCancelled: Task.isCancelled)
                    return FilePreviewReadResult(data: Data("slow preview".utf8), fileSize: 12)
                }
            )
        }

        XCTAssertTrue(probe.waitUntilStarted(timeout: 1), "Preview read did not start.")
        task.cancel()
        _ = await task.value

        XCTAssertTrue(probe.observedCancellation, "Stale preview reads should receive cancellation.")
    }

    func testBinaryPayloadInTextFileShowsUnsupportedPreview() async throws {
        let file = tempDirectory.appendingPathComponent("maybe.txt")
        try Data([0x66, 0x6f, 0x00, 0x6f]).write(to: file)

        let content = await FilePreviewContentLoader.loadContent(for: makeEntry(url: file, extension: "txt"))

        XCTAssertEqual(content, .unsupported(message: "Binary file preview is not available."))
    }

    func testImageFileUsesVisualPreview() async {
        let file = tempDirectory.appendingPathComponent("photo.png")

        let content = await FilePreviewContentLoader.loadContent(for: makeEntry(url: file, extension: "png"))

        XCTAssertEqual(content, .visual)
    }

    func testMissingTextFileShowsReadError() async {
        let file = tempDirectory.appendingPathComponent("missing.json")

        let content = await FilePreviewContentLoader.loadContent(for: makeEntry(url: file, extension: "json"))

        XCTAssertEqual(content, .unsupported(message: "Cannot read text preview."))
    }

    private func makeEntry(url: URL, extension fileExtension: String) -> FileEntry {
        FileEntry(
            url: url,
            name: url.lastPathComponent,
            kind: .file,
            typeDescription: fileExtension == "png" ? "PNG image" : "Text document",
            fileExtension: fileExtension,
            size: nil,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )
    }
}

private final class ThreadObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Bool] = []

    var values: [Bool] {
        lock.withLock {
            recordedValues
        }
    }

    func record(isMainThread: Bool) {
        lock.withLock {
            recordedValues.append(isMainThread)
        }
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private let timeoutDate = Date().addingTimeInterval(1)
    private var cancellationValues: [Bool] = []

    var hasTimedOut: Bool {
        Date() >= timeoutDate
    }

    var observedCancellation: Bool {
        lock.withLock {
            cancellationValues.contains(true)
        }
    }

    func recordStarted() {
        started.signal()
    }

    func waitUntilStarted(timeout: TimeInterval) -> Bool {
        started.wait(timeout: .now() + timeout) == .success
    }

    func recordCancellation(isCancelled: Bool) {
        lock.withLock {
            cancellationValues.append(isCancelled)
        }
    }
}
