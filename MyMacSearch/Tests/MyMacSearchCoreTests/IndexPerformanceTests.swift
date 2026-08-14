import Foundation
import XCTest
@testable import MyMacSearchCore

final class IndexPerformanceTests: XCTestCase {
    func testMillionEntrySelectiveQueryWarmP95() async throws {
        guard ProcessInfo.processInfo.environment["MYMACSEARCH_RUN_MILLION_BENCHMARK"] == "1" else {
            throw XCTSkip("Set MYMACSEARCH_RUN_MILLION_BENCHMARK=1 to run the million-row benchmark.")
        }

        let fixture = try TemporaryIndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(id: "large", rootPath: "/mock")
        try await fixture.writer.beginScopeScan(scope, generation: 1)

        let entryCount = 1_000_000
        let batchSize = 10_000
        let insertionStart = ContinuousClock.now
        for batchStart in stride(from: 0, to: entryCount, by: batchSize) {
            let upperBound = min(batchStart + batchSize, entryCount)
            let entries = (batchStart..<upperBound).map(LargeIndexRegressionTests.makeEntry)
            try await fixture.writer.upsertBatch(
                entries,
                scopeID: scope.id,
                generation: 1
            )
        }
        try await fixture.writer.completeScopeScan(scopeID: scope.id, generation: 1)
        let insertionDuration = insertionStart.duration(to: .now)

        let query = try SearchQueryParser.parse("name:needle ext:swift path:Downloads")
        for _ in 0..<5 {
            _ = try await fixture.reader.search(query: query, limit: 200, after: nil)
        }

        var samples: [Double] = []
        for _ in 0..<30 {
            let start = ContinuousClock.now
            let page = try await fixture.reader.search(query: query, limit: 200, after: nil)
            samples.append(milliseconds(start.duration(to: .now)))
            XCTAssertEqual(page.entries.count, 100)
        }
        samples.sort()
        let p50 = samples[samples.count / 2]
        let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
        let databaseBytes = (try? FileManager.default.attributesOfItem(
            atPath: fixture.databaseURL.path
        )[.size] as? NSNumber)?.int64Value ?? 0

        print(
            "MYMACSEARCH_BENCHMARK entries=\(entryCount) "
                + "insert_seconds=\(seconds(insertionDuration)) "
                + "warm_p50_ms=\(p50) warm_p95_ms=\(p95) db_bytes=\(databaseBytes)"
        )
        XCTAssertLessThanOrEqual(p95, 100)
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private func seconds(_ duration: Duration) -> Double {
        milliseconds(duration) / 1_000
    }
}
