import Foundation
import XCTest
@testable import MyMacSearchAppSupport
@testable import MyMacSearchCore

final class SearchLibraryStoreTests: XCTestCase {
    func testRecentSearchesAreBoundedDeduplicatedAndNormalizeUnquotedWhitespace() throws {
        let fixture = try SearchLibraryFixture()
        defer { fixture.remove() }
        for index in 0..<25 {
            try fixture.store.recordRecent(
                query: "query-\(index)",
                sort: .nameAscending,
                usedAt: Date(timeIntervalSince1970: Double(index))
            )
        }
        try fixture.store.recordRecent(
            query: "  query-20   ",
            sort: .sizeLargest,
            usedAt: Date(timeIntervalSince1970: 100)
        )

        let library = try fixture.store.load()
        XCTAssertEqual(library.recent.count, 20)
        XCTAssertEqual(library.recent.first?.query, "query-20")
        XCTAssertEqual(library.recent.first?.sort, .sizeLargest)
        XCTAssertEqual(library.recent.filter { $0.query == "query-20" }.count, 1)
    }

    func testSavedSearchMutationsPersistStableIdentityAndOrder() throws {
        let fixture = try SearchLibraryFixture()
        defer { fixture.remove() }
        let first = try fixture.store.save(name: "Reports", query: "kind:pdf", sort: .relevance, at: Date(timeIntervalSince1970: 1))
        let second = try fixture.store.save(name: "Reports", query: "ext:swift", sort: .nameAscending, at: Date(timeIntervalSince1970: 2))

        try fixture.store.rename(id: first.id, name: "PDF Reports")
        try fixture.store.replace(id: second.id, query: "ext:md", sort: .modifiedNewest, at: Date(timeIntervalSince1970: 3))
        try fixture.store.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        var library = try fixture.store.load()
        XCTAssertEqual(library.saved.map(\.id), [second.id, first.id])
        XCTAssertEqual(library.saved[0].query, "ext:md")
        XCTAssertEqual(library.saved[1].name, "PDF Reports")

        try fixture.store.remove(id: first.id)
        library = try fixture.store.load()
        XCTAssertEqual(library.saved.map(\.id), [second.id])
    }

    func testCorruptPrimaryRecoversLastGoodLibrary() throws {
        let fixture = try SearchLibraryFixture()
        defer { fixture.remove() }
        try fixture.store.recordRecent(query: "first", sort: .relevance, usedAt: Date())
        try fixture.store.recordRecent(query: "second", sort: .relevance, usedAt: Date())
        try Data("not json".utf8).write(to: fixture.store.libraryURL, options: .atomic)

        let recovered = try fixture.store.load()

        XCTAssertEqual(recovered.recent.map(\.query), ["first"])
        XCTAssertTrue(fixture.store.didRecoverLastGood)
    }
}

private struct SearchLibraryFixture {
    let root: URL
    let store: SearchLibraryStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacSearchLibrary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = SearchLibraryStore(directoryURL: root)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
