import XCTest
@testable import MyMacSearchCore

final class SQLiteIndexTests: XCTestCase {
    func testLoadsPersistedScopeGenerationAndEventCheckpoint() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "home", rootPath: "/Users/test")
        try await fixture.writer.beginScopeScan(scope, generation: 7)
        try await fixture.writer.completeScopeScan(scopeID: scope.id, generation: 7)
        try await fixture.writer.updateEventCheckpoint(scopeID: scope.id, eventID: 42)

        let scopes = try SQLiteIndexReader.loadScopes(at: fixture.databaseURL)

        XCTAssertEqual(
            scopes,
            [IndexScope(
                id: "home",
                rootPath: "/Users/test",
                completedGeneration: 7,
                lastEventID: 42
            )]
        )
    }
    func testUpsertUpdatesFTSAndDeleteRemovesFTSRow() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "home", rootPath: "/Users/test")
        try await fixture.writer.beginScopeScan(scope, generation: 1)
        try await fixture.writer.upsertBatch(
            [.testEntry(path: "/Users/test/AnnualReport.swift")],
            scopeID: scope.id,
            generation: 1
        )

        var page = try await fixture.reader.search(
            query: SearchQueryParser.parse("report"),
            limit: 200,
            after: nil
        )
        XCTAssertEqual(page.entries.map(\.name), ["AnnualReport.swift"])

        try await fixture.writer.upsertBatch(
            [.testEntry(path: "/Users/test/RenamedNotes.swift")],
            scopeID: scope.id,
            generation: 1
        )
        try await fixture.writer.delete(path: "/Users/test/AnnualReport.swift")

        page = try await fixture.reader.search(
            query: SearchQueryParser.parse("report"),
            limit: 200,
            after: nil
        )
        XCTAssertTrue(page.entries.isEmpty)
    }

    func testCompletingGenerationPrunesOnlyOlderRowsInThatScope() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let home = IndexScope(id: "home", rootPath: "/Users/test")
        let external = IndexScope(id: "external", rootPath: "/Volumes/Drive", volumeType: .external)
        try await fixture.writer.beginScopeScan(home, generation: 1)
        try await fixture.writer.beginScopeScan(external, generation: 1)
        try await fixture.writer.upsertBatch(
            [.testEntry(path: "/Users/test/stale.txt"), .testEntry(path: "/Users/test/keep.txt")],
            scopeID: home.id,
            generation: 1
        )
        try await fixture.writer.upsertBatch(
            [.testEntry(path: "/Volumes/Drive/external.txt", scopeID: external.id)],
            scopeID: external.id,
            generation: 1
        )

        try await fixture.writer.beginScopeScan(home, generation: 2)
        try await fixture.writer.upsertBatch(
            [.testEntry(path: "/Users/test/keep.txt", generation: 2)],
            scopeID: home.id,
            generation: 2
        )
        try await fixture.writer.completeScopeScan(scopeID: home.id, generation: 2)

        let page = try await fixture.reader.search(query: SearchQuery(), limit: 200, after: nil)
        XCTAssertEqual(Set(page.entries.map(\.path)), ["/Users/test/keep.txt", "/Volumes/Drive/external.txt"])
        let health = try await SQLiteIndexHealthReader(databaseURL: fixture.databaseURL).snapshot(liveStates: [:])
        XCTAssertEqual(health.scopes.first { $0.scopeID == home.id }?.entryCount, 1)
        XCTAssertEqual(health.scopes.first { $0.scopeID == external.id }?.entryCount, 1)
    }

    func testDeleteDirectoryRemovesOnlyPathBoundaryDescendants() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "home", rootPath: "/scope")
        try await fixture.writer.beginScopeScan(scope, generation: 1)
        try await fixture.writer.upsertBatch(
            [
                .testEntry(path: "/scope/Foo", kind: .folder),
                .testEntry(path: "/scope/Foo/child.txt"),
                .testEntry(path: "/scope/Foobar/keep.txt")
            ],
            scopeID: scope.id,
            generation: 1
        )

        try await fixture.writer.delete(path: "/scope/Foo")

        let page = try await fixture.reader.search(query: SearchQuery(), limit: 200, after: nil)
        XCTAssertEqual(page.entries.map(\.path), ["/scope/Foobar/keep.txt"])
        let health = try await SQLiteIndexHealthReader(databaseURL: fixture.databaseURL).snapshot(liveStates: [:])
        XCTAssertEqual(health.totalEntryCount, 1)
    }
}
