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

    func testAllowsUserApplicationsInsideHomeEvenWhenHomeLivesUnderPrivateVar() {
        let home = URL(fileURLWithPath: "/private/var/folders/tester-home", isDirectory: true)
        let policy = ProtectionPolicy(homeDirectory: home)

        XCTAssertFalse(policy.isProtected(home.appendingPathComponent("Applications/Test.app", isDirectory: true)))
    }

    func testBlocksAllowedLibrarySymlinkThatResolvesIntoProtectedRoot() throws {
        let home = try TestFixtures.temporaryDirectory(named: "protection-symlink")
        let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let target = home.appendingPathComponent("Documents/Important Export", isDirectory: true)
        let symlink = cacheRoot.appendingPathComponent("com.example.link", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        let policy = ProtectionPolicy(homeDirectory: home)

        XCTAssertTrue(policy.isProtected(symlink))
    }
}
