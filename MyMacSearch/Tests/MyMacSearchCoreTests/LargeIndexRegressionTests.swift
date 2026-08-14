import Foundation
import XCTest
@testable import MyMacSearchCore

final class LargeIndexRegressionTests: XCTestCase {
    func testHundredThousandMetadataRowsReturnExactFilteredResults() async throws {
        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "large", rootPath: "/mock")
        try await fixture.writer.beginScopeScan(scope, generation: 1)

        let entryCount = 100_000
        let batchSize = 5_000
        for batchStart in stride(from: 0, to: entryCount, by: batchSize) {
            let upperBound = min(batchStart + batchSize, entryCount)
            let entries = (batchStart..<upperBound).map(Self.makeEntry)
            try await fixture.writer.upsertBatch(
                entries,
                scopeID: scope.id,
                generation: 1
            )
        }
        try await fixture.writer.completeScopeScan(scopeID: scope.id, generation: 1)

        let query = try SearchQueryParser.parse("name:needle ext:swift path:Downloads")
        let page = try await fixture.reader.search(query: query, limit: 200, after: nil)

        XCTAssertEqual(page.entries.count, 10)
        XCTAssertTrue(page.entries.allSatisfy { $0.name.contains("Needle") })
        XCTAssertTrue(page.entries.allSatisfy { $0.fileExtension == "swift" })
        XCTAssertTrue(page.entries.allSatisfy { $0.path.contains("/Downloads/") })
        XCTAssertNil(page.nextCursor)

        for sort in SearchSort.allCases {
            let request = SearchRequest(query: SearchQuery(), sort: sort)
            let first = try await fixture.reader.search(request: request, limit: 200, after: nil)
            let second = try await fixture.reader.search(request: request, limit: 200, after: first.nextCursor)
            let combined = first.entries + second.entries
            XCTAssertEqual(combined.count, 400, "sort: \(sort)")
            XCTAssertEqual(Set(combined.map(\.id)).count, 400, "duplicate page row for sort: \(sort)")
            XCTAssertEqual(
                combined.map(\.path),
                Self.expectedFirstPaths(count: 400, total: entryCount, sort: sort),
                "incorrect keyset order for sort: \(sort)"
            )
        }

        let sizeQuery = try SearchQueryParser.parse("size:1KB..2KB")
        let sizePage = try await fixture.reader.search(
            request: SearchRequest(query: sizeQuery, sort: .sizeSmallest),
            limit: 200,
            after: nil
        )
        XCTAssertEqual(sizePage.entries.map(\.sizeBytes), Array(stride(from: Int64(1_030), through: 2_040, by: 10)))

        let healthReader = try SQLiteIndexHealthReader(databaseURL: fixture.databaseURL)
        let healthStart = ContinuousClock.now
        let health = try await healthReader.snapshot(liveStates: [
            scope.id: ScopeRuntimeState(state: .watching)
        ])
        let healthMilliseconds = Self.milliseconds(healthStart.duration(to: .now))
        XCTAssertEqual(health.totalEntryCount, entryCount)
        XCTAssertEqual(health.scopes.first?.entryCount, entryCount)
        XCTAssertLessThan(healthMilliseconds, 250)
    }

    static func makeEntry(_ index: Int) -> IndexedEntry {
        let isNeedle = index.isMultiple(of: 10_000)
        let fileExtension = index.isMultiple(of: 5) ? "pdf" : "swift"
        let effectiveExtension = isNeedle ? "swift" : fileExtension
        let area = index.isMultiple(of: 2) ? "Downloads" : "Documents"
        let name = isNeedle
            ? "NeedleReport_\(index).\(effectiveExtension)"
            : "Project_\(index).\(effectiveExtension)"
        let path = "/mock/\(area)/Bucket_\(index % 1_000)/\(name)"
        return IndexedEntry(
            scopeID: "large",
            path: path,
            parentPath: URL(fileURLWithPath: path).deletingLastPathComponent().path,
            name: name,
            fileExtension: effectiveExtension,
            kind: effectiveExtension == "pdf" ? .pdf : .code,
            sizeBytes: Int64(index * 10),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
            isDirectory: false,
            isSymlink: false,
            isPackage: false,
            isHidden: false,
            scanGeneration: 1
        )
    }

    private static func expectedFirstPaths(
        count: Int,
        total: Int,
        sort: SearchSort
    ) -> [String] {
        let entries = (0..<total).map(makeEntry)
        var indices = Array(0..<total)
        switch sort {
        case .relevance, .modifiedNewest, .sizeLargest:
            indices.reverse()
        case .modifiedOldest, .sizeSmallest:
            break
        case .nameAscending:
            indices.sort { entries[$0].searchName < entries[$1].searchName }
        case .nameDescending:
            indices.sort { entries[$0].searchName > entries[$1].searchName }
        case .pathAscending:
            indices.sort { entries[$0].searchPath < entries[$1].searchPath }
        case .pathDescending:
            indices.sort { entries[$0].searchPath > entries[$1].searchPath }
        case .kindThenName:
            indices.sort {
                let left = entries[$0]
                let right = entries[$1]
                if left.kind.rawValue != right.kind.rawValue {
                    return left.kind.rawValue < right.kind.rawValue
                }
                return left.searchName < right.searchName
            }
        }
        return indices.prefix(count).map { entries[$0].path }
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
