import Foundation
import XCTest
@testable import MyMacSearchAppSupport
@testable import MyMacSearchCore

final class SearchWorkflowTests: XCTestCase {
    @MainActor
    func testOnlySuccessfulCurrentSearchIsRecordedAsRecent() async throws {
        let fixture = try WorkflowLibraryFixture()
        defer { fixture.remove() }
        let searcher = WorkflowSearcher(delays: ["old": .milliseconds(150)])
        let model = SearchViewModel(searcher: searcher, libraryStore: fixture.store, debounce: .zero)

        model.query = "old"
        model.query = "current"

        try await eventually { model.rows.map(\.name) == ["current.txt"] }
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(try fixture.store.load().recent.map(\.query), ["current"])
    }

    @MainActor
    func testTokenRemovalPreservesOtherTextAndQuotedValue() async throws {
        let fixture = try WorkflowLibraryFixture()
        defer { fixture.remove() }
        let model = SearchViewModel(searcher: WorkflowSearcher(), libraryStore: fixture.store, debounce: .zero)
        model.query = #"report kind:pdf path:"Project Files""#
        try await eventually { model.tokens.count == 2 }

        model.removeToken(id: model.tokens[0].id)

        XCTAssertEqual(model.query, #"report path:"Project Files""#)
    }

    @MainActor
    func testSavedSearchRestoresQueryAndSort() async throws {
        let fixture = try WorkflowLibraryFixture()
        defer { fixture.remove() }
        let saved = try fixture.store.save(name: "Large PDFs", query: "kind:pdf size:>100MB", sort: .sizeLargest, at: Date())
        let model = SearchViewModel(searcher: WorkflowSearcher(), libraryStore: fixture.store, debounce: .zero)

        model.activateSavedSearch(saved.id)

        XCTAssertEqual(model.query, "kind:pdf size:>100MB")
        XCTAssertEqual(model.sort, .sizeLargest)
    }

    @MainActor
    func testPrimarySelectionTracksNewestAddedAndFallsBackInVisibleOrder() async throws {
        let model = SearchViewModel(searcher: MultiSelectionSearcher(), debounce: .zero)
        model.query = "multi"
        try await eventually { model.rows.count == 3 }

        model.updateSelection([1])
        model.updateSelection([1, 3])
        XCTAssertEqual(model.primaryEntryID, 3)

        model.updateSelection([1])
        XCTAssertEqual(model.primaryEntryID, 1)
    }
}

private actor MultiSelectionSearcher: IndexSearching {
    func search(request: SearchRequest, limit: Int, after cursor: SearchPageCursor?) async throws -> SearchPage {
        SearchPage(
            entries: [
                .workflowFixture(id: 1, name: "one.txt"),
                .workflowFixture(id: 2, name: "two.txt"),
                .workflowFixture(id: 3, name: "three.txt")
            ],
            nextCursor: nil
        )
    }
}

private actor WorkflowSearcher: IndexSearching {
    let delays: [String: Duration]

    init(delays: [String: Duration] = [:]) { self.delays = delays }

    func search(request: SearchRequest, limit: Int, after cursor: SearchPageCursor?) async throws -> SearchPage {
        let term = request.query.freeTerms.first ?? request.query.kinds.first?.rawValue ?? "empty"
        if let delay = delays[term] { try? await Task.sleep(for: delay) }
        return SearchPage(entries: [.workflowFixture(name: "\(term).txt")], nextCursor: nil)
    }
}

private extension IndexedEntry {
    static func workflowFixture(id: Int64 = 1, name: String) -> IndexedEntry {
        IndexedEntry(
            id: id,
            scopeID: "scope",
            path: "/scope/\(name)",
            parentPath: "/scope",
            name: name,
            fileExtension: "txt",
            kind: .document,
            sizeBytes: 1,
            modifiedAt: Date(),
            isDirectory: false,
            isSymlink: false,
            isPackage: false,
            isHidden: false,
            scanGeneration: 1
        )
    }
}

private struct WorkflowLibraryFixture {
    let root: URL
    let store: SearchLibraryStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Workflow-\(UUID().uuidString)")
        store = SearchLibraryStore(directoryURL: root)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Condition was not met")
}
