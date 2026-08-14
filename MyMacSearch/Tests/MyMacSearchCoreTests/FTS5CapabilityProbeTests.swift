import XCTest
@testable import MyMacSearchCore

final class FTS5CapabilityProbeTests: XCTestCase {
    func testSystemSQLiteSupportsRequiredFTS5TrigramBehavior() throws {
        XCTAssertNoThrow(try FTS5CapabilityProbe.verify())
    }

    func testUnknownTokenizerFailsWithCapabilityError() {
        XCTAssertThrowsError(try FTS5CapabilityProbe.verify(tokenizer: "missing_mymacsearch_tokenizer")) { error in
            guard case SQLiteIndexError.capabilityUnavailable = error else {
                return XCTFail("Expected capabilityUnavailable, got \(error)")
            }
        }
    }
}
