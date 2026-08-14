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
}
