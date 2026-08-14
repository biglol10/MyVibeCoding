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

    func testNameSortUsesEntryIDAsFinalTieBreakerAcrossPages() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "home", rootPath: "/scope")
        try await fixture.writer.beginScopeScan(scope, generation: 1)
        try await fixture.writer.upsertBatch(
            [
                .testEntry(path: "/z/Report.swift"),
                .testEntry(path: "/a/report.swift"),
                .testEntry(path: "/b/REPORT.swift")
            ],
            scopeID: scope.id,
            generation: 1
        )

        let request = SearchRequest(query: SearchQuery(), sort: .nameAscending)
        let first = try await fixture.reader.search(request: request, limit: 2, after: nil)
        let second = try await fixture.reader.search(request: request, limit: 2, after: first.nextCursor)

        XCTAssertEqual((first.entries + second.entries).map(\.path), [
            "/z/Report.swift", "/a/report.swift", "/b/REPORT.swift"
        ])
        XCTAssertEqual(Set((first.entries + second.entries).map(\.id)).count, 3)
    }

    func testAllMetadataSortsReturnDeterministicLiteralOrder() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "home", rootPath: "/scope")
        try await fixture.writer.beginScopeScan(scope, generation: 1)
        try await fixture.writer.upsertBatch(
            [
                .testEntry(path: "/z/a.swift", kind: .code, sizeBytes: 100, modifiedAt: Date(timeIntervalSince1970: 100)),
                .testEntry(path: "/a/b.pdf", kind: .pdf, sizeBytes: 300, modifiedAt: Date(timeIntervalSince1970: 300)),
                .testEntry(path: "/m/c", kind: .folder, sizeBytes: 200, modifiedAt: Date(timeIntervalSince1970: 200))
            ],
            scopeID: scope.id,
            generation: 1
        )
        let cases: [(SearchSort, [String])] = [
            (.nameAscending, ["a.swift", "b.pdf", "c"]),
            (.nameDescending, ["c", "b.pdf", "a.swift"]),
            (.pathAscending, ["b.pdf", "c", "a.swift"]),
            (.pathDescending, ["a.swift", "c", "b.pdf"]),
            (.modifiedNewest, ["b.pdf", "c", "a.swift"]),
            (.modifiedOldest, ["a.swift", "c", "b.pdf"]),
            (.sizeLargest, ["b.pdf", "c", "a.swift"]),
            (.sizeSmallest, ["a.swift", "c", "b.pdf"]),
            (.kindThenName, ["a.swift", "c", "b.pdf"])
        ]

        for (sort, expectedNames) in cases {
            let page = try await fixture.reader.search(
                request: SearchRequest(query: SearchQuery(), sort: sort),
                limit: 20,
                after: nil
            )
            XCTAssertEqual(page.entries.map(\.name), expectedNames, "sort: \(sort)")
        }
    }

    func testSizeRangesUseBoundPredicatesAtExactBoundaries() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "home", rootPath: "/scope")
        try await fixture.writer.beginScopeScan(scope, generation: 1)
        try await fixture.writer.upsertBatch(
            [
                .testEntry(path: "/scope/small.bin", sizeBytes: 99),
                .testEntry(path: "/scope/lower.bin", sizeBytes: 100),
                .testEntry(path: "/scope/inside.bin", sizeBytes: 150),
                .testEntry(path: "/scope/upper.bin", sizeBytes: 200)
            ],
            scopeID: scope.id,
            generation: 1
        )

        let page = try await fixture.reader.search(
            request: SearchRequest(
                query: SearchQuery(sizeRange: .closed(100, 200)),
                sort: .sizeSmallest
            ),
            limit: 20,
            after: nil
        )

        XCTAssertEqual(page.entries.map(\.name), ["lower.bin", "inside.bin", "upper.bin"])
    }
}
