import XCTest
@testable import MyMacCleanCore

final class ProtectionPolicyTests: XCTestCase {
    func testBlocksUserDocumentFoldersAndSystemCriticalPaths() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let policy = ProtectionPolicy(homeDirectory: home)

        XCTAssertTrue(policy.isProtected(URL(fileURLWithPath: "/Users/tester/Documents/Figma Export.fig")))
        XCTAssertTrue(policy.isProtected(URL(fileURLWithPath: "/Users/tester/Desktop/Sketch.sketch")))
        XCTAssertTrue(policy.isProtected(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")))
        XCTAssertTrue(policy.isProtected(URL(fileURLWithPath: "/private/var/db/example")))
    }

    func testAllowsKnownUserLibraryAppData() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let policy = ProtectionPolicy(homeDirectory: home)

        XCTAssertFalse(policy.isProtected(URL(fileURLWithPath: "/Users/tester/Library/Caches/com.figma.Desktop")))
        XCTAssertFalse(policy.isProtected(URL(fileURLWithPath: "/Users/tester/Library/Application Support/Figma")))
    }
}
