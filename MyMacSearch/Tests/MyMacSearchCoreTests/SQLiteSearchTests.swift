import XCTest
@testable import MyMacSearchCore

final class SQLiteSearchTests: XCTestCase {
    func testSubstringPunctuationAndStructuredFiltersUseBoundValues() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "home", rootPath: "/Users/test")
        try await fixture.writer.beginScopeScan(scope, generation: 1)
        try await fixture.writer.upsertBatch(
            [
                .testEntry(
                    path: "/Users/test/Downloads/AnnualReport.swift",
                    sizeBytes: 500,
                    modifiedAt: Date(timeIntervalSince1970: 1_723_500_000)
                ),
                .testEntry(
                    path: "/Users/test/Documents/Report.pdf",
                    kind: .pdf,
                    modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
                ),
                .testEntry(path: "/Users/test/Downloads/Notes.txt")
            ],
            scopeID: scope.id,
            generation: 1
        )

        let punctuation = try await fixture.reader.search(
            query: SearchQueryParser.parse(#"name:"port.s""#),
            limit: 200,
            after: nil
        )
        XCTAssertEqual(punctuation.entries.map(\.name), ["AnnualReport.swift"])

        let filtered = try await fixture.reader.search(
            query: SearchQueryParser.parse(
                "path:Downloads ext:swift kind:code modified:7d",
                now: Date(timeIntervalSince1970: 1_723_593_600),
                calendar: Calendar(identifier: .gregorian)
            ),
            limit: 200,
            after: nil
        )
        XCTAssertEqual(filtered.entries.map(\.name), ["AnnualReport.swift"])
    }

    func testShortTextUsesFilenamePrefix() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "home", rootPath: "/scope")
        try await fixture.writer.beginScopeScan(scope, generation: 1)
        try await fixture.writer.upsertBatch(
            [.testEntry(path: "/scope/GoServer.swift"), .testEntry(path: "/scope/Logo.swift")],
            scopeID: scope.id,
            generation: 1
        )

        let page = try await fixture.reader.search(
            query: SearchQueryParser.parse("go"),
            limit: 200,
            after: nil
        )

        XCTAssertEqual(page.entries.map(\.name), ["GoServer.swift"])
    }
}
