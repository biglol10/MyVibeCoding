import XCTest
@testable import MyMacCleanCore

final class UserFileCleanupPolicyTests: XCTestCase {
    func testAllowsFilesInsideExplicitScanRoot() throws {
        let root = try TestFixtures.temporaryDirectory(named: "user-file-policy")
        let file = root.appendingPathComponent("movie.mov")
        try Data(repeating: 1, count: 8).write(to: file)

        let policy = UserFileCleanupPolicy(allowedRoots: [root])

        XCTAssertFalse(policy.isProtected(file))
    }

    func testBlocksFilesOutsideExplicitScanRoot() throws {
        let allowed = try TestFixtures.temporaryDirectory(named: "user-file-policy-allowed")
        let outside = try TestFixtures.temporaryDirectory(named: "user-file-policy-outside")
        let file = outside.appendingPathComponent("movie.mov")
        try Data(repeating: 1, count: 8).write(to: file)

        let policy = UserFileCleanupPolicy(allowedRoots: [allowed])

        XCTAssertTrue(policy.isProtected(file))
    }

    func testBlocksSystemRootsEvenWhenPassedAsAllowedRoot() {
        let policy = UserFileCleanupPolicy(allowedRoots: [URL(fileURLWithPath: "/System", isDirectory: true)])

        XCTAssertTrue(policy.isProtected(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")))
    }
}
