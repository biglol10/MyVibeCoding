import Foundation
import XCTest
@testable import MyMacFinder

final class SecurityScopedBookmarkStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MyMacFinderTests.SecurityScopedBookmarkStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveLoadAndRemoveGrant() throws {
        let store = SecurityScopedBookmarkStore(defaults: defaults)
        let grant = FolderAccessGrant(
            id: FolderAccessGrantID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
            url: URL(fileURLWithPath: "/Users/biglol/Documents", isDirectory: true),
            bookmarkData: Data([1, 2, 3]),
            createdAt: Date(timeIntervalSince1970: 10),
            lastResolvedAt: nil
        )

        try store.save(grant)
        XCTAssertEqual(store.load(), [grant])

        store.remove(id: grant.id)
        XCTAssertEqual(store.load(), [])
    }

    func testResetRemovesAllGrants() throws {
        let store = SecurityScopedBookmarkStore(defaults: defaults)
        try store.save(FolderAccessGrant(url: URL(fileURLWithPath: "/tmp/a", isDirectory: true), bookmarkData: Data([1])))
        try store.save(FolderAccessGrant(url: URL(fileURLWithPath: "/tmp/b", isDirectory: true), bookmarkData: Data([2])))

        store.reset()

        XCTAssertEqual(store.load(), [])
    }

    func testSavingSameURLReplacesExistingGrant() throws {
        let store = SecurityScopedBookmarkStore(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/folder", isDirectory: true)
        try store.save(FolderAccessGrant(url: url, bookmarkData: Data([1]), createdAt: Date(timeIntervalSince1970: 1)))
        try store.save(FolderAccessGrant(url: url, bookmarkData: Data([9]), createdAt: Date(timeIntervalSince1970: 2)))

        let grants = store.load()
        XCTAssertEqual(grants.count, 1)
        XCTAssertEqual(grants[0].url, url.standardizedFileURL)
        XCTAssertEqual(grants[0].bookmarkData, Data([9]))
    }
}
