import XCTest
import AppKit
@testable import CaptureStudio

final class CaptureHistoryStoreTests: XCTestCase {
    @MainActor
    func testAddingHistoryItemPersistsNewestFirst() {
        let defaults = isolatedDefaults("persist")
        let older = CaptureHistoryItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: 10),
            fileURL: URL(fileURLWithPath: "/tmp/older.png"),
            title: "Older capture",
            detail: "Safari",
            thumbnailData: Data([1]),
            sourceApplication: "Safari",
            windowTitle: "Docs"
        )
        let newer = CaptureHistoryItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            kind: .recording,
            createdAt: Date(timeIntervalSince1970: 20),
            fileURL: URL(fileURLWithPath: "/tmp/newer.mp4"),
            title: "Newer recording",
            detail: "Chrome",
            sourceApplication: "Chrome",
            windowTitle: "Bug"
        )
        let store = CaptureHistoryStore(defaults: defaults)

        store.add(older)
        store.add(newer)

        let reloaded = CaptureHistoryStore(defaults: defaults)
        var persistedOlder = older
        persistedOlder.thumbnailData = nil
        XCTAssertEqual(reloaded.items, [newer, persistedOlder])
    }

    @MainActor
    func testSearchMatchesTitleApplicationAndWindowTitle() {
        let store = CaptureHistoryStore(defaults: isolatedDefaults("search"))
        store.add(
            CaptureHistoryItem(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: URL(fileURLWithPath: "/tmp/naver.png"),
                title: "Naver checkout capture",
                detail: "Google Chrome",
                sourceApplication: "Google Chrome",
                windowTitle: "Checkout Issue"
            )
        )
        store.add(
            CaptureHistoryItem(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 20),
                fileURL: URL(fileURLWithPath: "/tmp/finder.png"),
                title: "Finder capture",
                detail: "Finder",
                sourceApplication: "Finder",
                windowTitle: "Downloads"
            )
        )

        XCTAssertEqual(store.items(matching: "checkout").map(\.title), ["Naver checkout capture"])
        XCTAssertEqual(store.items(matching: "chrome").map(\.title), ["Naver checkout capture"])
        XCTAssertEqual(store.items(matching: "downloads").map(\.title), ["Finder capture"])
    }

    @MainActor
    func testStoreCapsHistoryToConfiguredLimit() {
        let store = CaptureHistoryStore(defaults: isolatedDefaults("limit"), maxItems: 2)

        store.add(item(title: "first", date: 10))
        store.add(item(title: "second", date: 20))
        store.add(item(title: "third", date: 30))

        XCTAssertEqual(store.items.map(\.title), ["third", "second"])
    }

    @MainActor
    func testRemovingHistoryItemPersistsRemoval() {
        let defaults = isolatedDefaults("remove")
        let item = item(title: "remove me", date: 10)
        let store = CaptureHistoryStore(defaults: defaults)
        store.add(item)

        store.remove(id: item.id)

        XCTAssertTrue(CaptureHistoryStore(defaults: defaults).items.isEmpty)
    }

    @MainActor
    func testScreenshotHistoryWritesThumbnailFileAndDoesNotPersistImageBytesInDefaults() throws {
        let defaults = isolatedDefaults("thumbnailPayload")
        let thumbnailDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        let fullSizeData = try pngData(width: 1400, height: 900)
        let store = CaptureHistoryStore(
            defaults: defaults,
            maxItems: 100,
            thumbnailDirectory: thumbnailDirectory
        )

        store.add(
            CaptureHistoryItem(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: URL(fileURLWithPath: "/tmp/large.png"),
                title: "Large screenshot",
                detail: "Screenshot",
                thumbnailData: fullSizeData
            )
        )

        let storedItem = try XCTUnwrap(store.items.first)
        let thumbnailURL = try XCTUnwrap(storedItem.thumbnailURL)
        let persistedData = try XCTUnwrap(defaults.data(forKey: "CaptureStudio.CaptureHistory.v1"))
        let persistedJSON = try XCTUnwrap(String(data: persistedData, encoding: .utf8))
        let thumbnailAttributes = try FileManager.default.attributesOfItem(atPath: thumbnailURL.path)
        let thumbnailSize = try XCTUnwrap(thumbnailAttributes[FileAttributeKey.size] as? NSNumber).intValue

        XCTAssertNil(storedItem.thumbnailData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))
        XCTAssertLessThan(thumbnailSize, fullSizeData.count)
        XCTAssertFalse(persistedJSON.contains(fullSizeData.base64EncodedString()))
        XCTAssertEqual(CaptureHistoryStore(defaults: defaults, thumbnailDirectory: thumbnailDirectory).items.first?.thumbnailURL, thumbnailURL)
    }

    @MainActor
    func testRemovingHistoryItemDeletesThumbnailFile() throws {
        let thumbnailDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = CaptureHistoryStore(
            defaults: isolatedDefaults("thumbnailRemoval"),
            thumbnailDirectory: thumbnailDirectory
        )
        store.add(
            CaptureHistoryItem(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: URL(fileURLWithPath: "/tmp/remove-thumbnail.png"),
                title: "Remove thumbnail",
                detail: "Screenshot",
                thumbnailData: try pngData(width: 800, height: 600)
            )
        )
        let item = try XCTUnwrap(store.items.first)
        let thumbnailURL = try XCTUnwrap(item.thumbnailURL)

        store.remove(id: item.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnailURL.path))
    }

    @MainActor
    func testClearRemovesAllHistoryMetadataAndThumbnailFiles() throws {
        let defaults = isolatedDefaults("clear")
        let thumbnailDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: thumbnailDirectory) }
        let store = CaptureHistoryStore(defaults: defaults, thumbnailDirectory: thumbnailDirectory)
        store.add(
            CaptureHistoryItem(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: URL(fileURLWithPath: "/tmp/clear-thumbnail.png"),
                title: "Clear thumbnail",
                detail: "Screenshot",
                thumbnailData: try pngData(width: 800, height: 600)
            )
        )
        store.add(item(title: "record only", date: 20))
        let thumbnailURL = try XCTUnwrap(store.items.first(where: { $0.thumbnailURL != nil })?.thumbnailURL)

        store.clear()

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(CaptureHistoryStore(defaults: defaults, thumbnailDirectory: thumbnailDirectory).items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnailURL.path))
    }

    @MainActor
    func testFailedThumbnailWriteDoesNotPersistMissingThumbnailURL() throws {
        let parentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parentDirectory) }
        let nonDirectoryURL = parentDirectory.appendingPathComponent("not-a-directory")
        try Data("blocking file".utf8).write(to: nonDirectoryURL)
        let store = CaptureHistoryStore(
            defaults: isolatedDefaults("thumbnailWriteFailure"),
            thumbnailDirectory: nonDirectoryURL
        )

        store.add(
            CaptureHistoryItem(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: URL(fileURLWithPath: "/tmp/missing-thumbnail.png"),
                title: "Missing thumbnail",
                detail: "Screenshot",
                thumbnailData: try pngData(width: 800, height: 600)
            )
        )

        XCTAssertNil(store.items.first?.thumbnailURL)
    }

    @MainActor
    func testRemovingHistoryNeverDeletesThumbnailPathOutsideOwnedDirectory() throws {
        let defaults = isolatedDefaults("unownedThumbnail")
        let parentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        let thumbnailDirectory = parentDirectory.appendingPathComponent("owned", isDirectory: true)
        let protectedURL = parentDirectory.appendingPathComponent("protected.txt")
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: protectedURL)
        defer { try? FileManager.default.removeItem(at: parentDirectory) }
        let item = CaptureHistoryItem(
            kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: 10),
            fileURL: URL(fileURLWithPath: "/tmp/capture.png"),
            title: "Capture",
            detail: "Screenshot",
            thumbnailURL: protectedURL
        )
        defaults.set(try JSONEncoder().encode([item]), forKey: "CaptureStudio.CaptureHistory.v1")
        let store = CaptureHistoryStore(defaults: defaults, thumbnailDirectory: thumbnailDirectory)

        let cleanupSucceeded = store.remove(id: item.id)

        XCTAssertFalse(cleanupSucceeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedURL.path))
        XCTAssertEqual(try Data(contentsOf: protectedURL), Data("keep me".utf8))
    }

    @MainActor
    func testFileIdentityPersistsWithHistoryMetadata() throws {
        let defaults = isolatedDefaults("fileIdentity")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureHistoryStoreTests-\(UUID().uuidString).png")
        try Data("capture".utf8).write(to: fileURL)
        let identity = try CaptureFileIdentity.existingFile(at: fileURL)
        let item = CaptureHistoryItem(
            kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: 10),
            fileURL: fileURL,
            title: "Capture",
            detail: "Screenshot",
            fileIdentity: identity
        )
        let store = CaptureHistoryStore(defaults: defaults)

        store.add(item)

        XCTAssertEqual(CaptureHistoryStore(defaults: defaults).items.first?.fileIdentity, identity)
    }

    private func item(title: String, date: TimeInterval) -> CaptureHistoryItem {
        CaptureHistoryItem(
            kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: date),
            fileURL: URL(fileURLWithPath: "/tmp/\(title).png"),
            title: title,
            detail: "CaptureStudio",
            sourceApplication: "CaptureStudio",
            windowTitle: title
        )
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CaptureHistoryStoreTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func pngData(width: CGFloat, height: CGFloat) throws -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        image.unlockFocus()

        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }
}
