import Foundation
import XCTest
@testable import MyMacSearchAppSupport
@testable import MyMacSearchCore

final class SearchViewModelTests: XCTestCase {
    @MainActor
    func testSlowOldQueryCannotReplaceNewResults() async throws {
        let searcher = DelayedSearcher(delays: ["old": .milliseconds(180)])
        let model = SearchViewModel(searcher: searcher, debounce: .zero)

        model.query = "old"
        try await Task.sleep(for: .milliseconds(20))
        model.query = "new"

        try await eventually { model.rows.map(\.name) == ["new.swift"] }
        try await Task.sleep(for: .milliseconds(220))
        XCTAssertEqual(model.rows.map(\.name), ["new.swift"])
    }

    @MainActor
    func testParserErrorKeepsLastGoodRowsAndSkipsDatabase() async throws {
        let searcher = DelayedSearcher()
        let model = SearchViewModel(searcher: searcher, debounce: .zero)
        model.query = "valid"
        try await eventually { model.rows.map(\.name) == ["valid.swift"] }
        let callCount = await searcher.callCount

        model.query = "unknown:value"
        try await eventually { model.parserError != nil }

        XCTAssertEqual(model.rows.map(\.name), ["valid.swift"])
        let finalCallCount = await searcher.callCountValue()
        XCTAssertEqual(finalCallCount, callCount)
    }

    @MainActor
    func testLoadMoreAppendsKeysetPageWithoutDuplicatingRows() async throws {
        let searcher = PaginatedSearcher()
        let model = SearchViewModel(searcher: searcher, debounce: .zero, pageSize: 2)
        model.query = "report"
        try await eventually { model.rows.map(\.name) == ["one.txt", "two.txt"] }

        model.loadMore()
        try await eventually {
            model.rows.map(\.name) == ["one.txt", "two.txt", "three.txt"]
        }

        XCTAssertFalse(model.canLoadMore)
        let cursors = await searcher.receivedCursors()
        XCTAssertEqual(cursors, [nil, SearchPageCursor.fixture])
    }
}

private actor DelayedSearcher: IndexSearching {
    private let delays: [String: Duration]
    private(set) var callCount = 0

    init(delays: [String: Duration] = [:]) {
        self.delays = delays
    }

    func search(
        request: SearchRequest,
        limit: Int,
        after cursor: SearchPageCursor?
    ) async throws -> SearchPage {
        callCount += 1
        let query = request.query
        let term = query.freeTerms.first ?? query.nameTerms.first ?? "empty"
        if let delay = delays[term] {
            try? await Task.sleep(for: delay)
        }
        return SearchPage(entries: [.fixture(name: "\(term).swift")], nextCursor: nil)
    }

    func callCountValue() -> Int { callCount }
}

private actor PaginatedSearcher: IndexSearching {
    private var cursors: [SearchPageCursor?] = []

    func search(
        request: SearchRequest,
        limit: Int,
        after cursor: SearchPageCursor?
    ) async throws -> SearchPage {
        cursors.append(cursor)
        if cursor == nil {
            return SearchPage(
                entries: [.fixture(id: 1, name: "one.txt"), .fixture(id: 2, name: "two.txt")],
                nextCursor: .fixture
            )
        }
        return SearchPage(
            entries: [.fixture(id: 2, name: "two.txt"), .fixture(id: 3, name: "three.txt")],
            nextCursor: nil
        )
    }

    func receivedCursors() -> [SearchPageCursor?] { cursors }
}

private extension SearchPageCursor {
    static let fixture = SearchPageCursor.relevance(
        rank: 1,
        modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        entryID: 2
    )
}

private extension IndexedEntry {
    static func fixture(id: Int64 = 1, name: String) -> IndexedEntry {
        IndexedEntry(
            id: id,
            scopeID: "scope",
            path: "/scope/\(name)",
            parentPath: "/scope",
            name: name,
            fileExtension: URL(fileURLWithPath: name).pathExtension,
            kind: .code,
            sizeBytes: 1,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isDirectory: false,
            isSymlink: false,
            isPackage: false,
            isHidden: false,
            scanGeneration: 1
        )
    }
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !(await condition()) {
        if clock.now >= deadline {
            XCTFail("Condition did not become true before timeout")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
