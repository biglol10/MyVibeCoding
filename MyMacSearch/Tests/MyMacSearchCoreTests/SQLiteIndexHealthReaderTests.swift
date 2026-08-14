import Foundation
import XCTest
@testable import MyMacSearchCore

final class SQLiteIndexHealthReaderTests: XCTestCase {
    func testSnapshotAggregatesCountsIssuesAndLiveStateByScope() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let home = IndexScope(id: "home", rootPath: "/Users/test")
        let work = IndexScope(id: "work", rootPath: "/Volumes/Work", volumeType: .external)
        try await fixture.writer.beginScopeScan(home, generation: 1)
        try await fixture.writer.beginScopeScan(work, generation: 1)
        try await fixture.writer.upsertBatch(
            [.testEntry(path: "/Users/test/a.swift"), .testEntry(path: "/Users/test/b.swift")],
            scopeID: home.id,
            generation: 1
        )
        try await fixture.writer.upsertBatch(
            [.testEntry(path: "/Volumes/Work/c.pdf", scopeID: work.id)],
            scopeID: work.id,
            generation: 1
        )
        try await fixture.writer.recordIssue(
            scopeID: work.id,
            path: work.rootPath,
            category: .unavailableRoot,
            message: "offline",
            occurredAt: Date(timeIntervalSince1970: 50)
        )
        let reader = try SQLiteIndexHealthReader(databaseURL: fixture.databaseURL)

        let snapshot = try await reader.snapshot(liveStates: [
            "home": ScopeRuntimeState(state: .watching),
            "work": ScopeRuntimeState(state: .offline, message: "offline")
        ])

        XCTAssertEqual(snapshot.totalEntryCount, 3)
        XCTAssertEqual(snapshot.scopes.first { $0.scopeID == "home" }?.entryCount, 2)
        XCTAssertEqual(snapshot.scopes.first { $0.scopeID == "work" }?.unresolvedIssueCount, 1)
        XCTAssertEqual(snapshot.scopes.first { $0.scopeID == "work" }?.state, .offline)
        XCTAssertGreaterThan(snapshot.databaseBytes, 0)
    }

    func testIssuePageClampsLimitAndReturnsNewestFirst() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "home", rootPath: "/Users/test")
        try await fixture.writer.beginScopeScan(scope, generation: 1)
        for index in 0..<3 {
            try await fixture.writer.recordIssue(
                scopeID: scope.id,
                path: "/path/\(index)",
                category: .metadataRead,
                message: "issue \(index)",
                occurredAt: Date(timeIntervalSince1970: Double(index))
            )
        }
        let reader = try SQLiteIndexHealthReader(databaseURL: fixture.databaseURL)

        let issues = try await reader.issues(scopeID: scope.id, unresolvedOnly: true, limit: 2)

        XCTAssertEqual(issues.map(\.path), ["/path/2", "/path/1"])
    }
}
