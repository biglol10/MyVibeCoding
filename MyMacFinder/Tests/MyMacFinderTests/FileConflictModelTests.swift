import XCTest
@testable import MyMacFinder

final class FileConflictModelTests: XCTestCase {
    func testDefaultResolverReturnsConfiguredDecision() async throws {
        let source = URL(fileURLWithPath: "/tmp/source.txt")
        let destination = URL(fileURLWithPath: "/tmp/dest.txt")
        let conflict = FileConflict(
            operation: .copy,
            sourceURL: source,
            destinationURL: destination,
            itemIndex: 2,
            itemCount: 5
        )
        let resolver = DefaultFileConflictResolver(decision: .keepBoth)

        let decision = try await resolver.resolve(conflict)

        XCTAssertEqual(decision, .keepBoth)
        XCTAssertEqual(conflict.displayName, "source.txt")
        XCTAssertEqual(conflict.progressDescription, "3 of 5")
    }

    func testCancelDecisionThrowsCancellationError() async {
        let resolver = DefaultFileConflictResolver(decision: .cancel)
        let conflict = FileConflict(
            operation: .move,
            sourceURL: URL(fileURLWithPath: "/tmp/a.txt"),
            destinationURL: URL(fileURLWithPath: "/tmp/b.txt"),
            itemIndex: 0,
            itemCount: 1
        )

        do {
            _ = try await resolver.resolve(conflict)
            XCTFail("Expected cancellation")
        } catch let error as FileOperationCancellation {
            XCTAssertEqual(error.operation, .move)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
