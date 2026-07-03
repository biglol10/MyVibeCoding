import XCTest
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
        XCTAssertEqual(reloaded.items, [newer, older])
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
}
