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
