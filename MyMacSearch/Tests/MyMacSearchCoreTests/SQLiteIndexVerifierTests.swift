import Foundation
import XCTest
@testable import MyMacSearchCore

final class SQLiteIndexVerifierTests: XCTestCase {
    func testHealthyIndexPassesSchemaQuickCheckFTSAndRowCount() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "home", rootPath: "/Users/test")
        try await fixture.writer.beginScopeScan(scope, generation: 1)
        try await fixture.writer.upsertBatch(
            [.testEntry(path: "/Users/test/report.swift")],
            scopeID: scope.id,
            generation: 1
        )
        let verifier = SQLiteIndexVerifier(databaseURL: fixture.databaseURL)

        let result = try await verifier.verify()

        XCTAssertTrue(result.isHealthy)
        XCTAssertEqual(result.checks.map(\.name), ["Schema", "SQLite", "FTS5", "Entry consistency", "Scope roots"])
        XCTAssertTrue(result.checks.allSatisfy(\.passed))
    }

    func testEntryOutsideConfiguredRootFailsVerification() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "home", rootPath: "/Users/test")
        try await fixture.writer.beginScopeScan(scope, generation: 1)
        try await fixture.writer.upsertBatch(
            [.testEntry(path: "/Volumes/Other/report.swift")],
            scopeID: scope.id,
            generation: 1
        )

        let result = try await SQLiteIndexVerifier(databaseURL: fixture.databaseURL).verify()

        XCTAssertEqual(result.checks.first { $0.name == "Scope roots" }?.passed, false)
    }
}
