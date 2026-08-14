import XCTest
@testable import MyMacSearchCore

final class IndexingPolicyTests: XCTestCase {
    func testBuiltInExclusionsUsePathAndDirectoryBoundaries() {
        let policy = IndexingPolicy(homePath: "/Users/test", includeHidden: false)

        XCTAssertEqual(policy.decision(for: .directory("/System")), .exclude)
        XCTAssertEqual(policy.decision(for: .directory("/Library/Logs")), .exclude)
        XCTAssertEqual(policy.decision(for: .directory("/Users/test/Library/Caches/app")), .exclude)
        XCTAssertEqual(policy.decision(for: .directory("/Users/test/Project/.git")), .exclude)
        XCTAssertEqual(policy.decision(for: .directory("/Users/test/Project/node_modules")), .exclude)
        XCTAssertEqual(policy.decision(for: .file("/Users/test/SystemNotes.txt")), .indexOnly)
        XCTAssertEqual(policy.decision(for: .directory("/Users/test/Project/.github")), .exclude)
    }

    func testSymlinkPackageAndHiddenPoliciesAreIndependent() {
        let hiddenOff = IndexingPolicy(homePath: "/Users/test", includeHidden: false)
        XCTAssertEqual(hiddenOff.decision(for: .symlink("/Users/test/link")), .indexOnly)
        XCTAssertEqual(hiddenOff.decision(for: .package("/Users/test/Tool.app")), .indexOnly)
        XCTAssertEqual(hiddenOff.decision(for: .hiddenFile("/Users/test/.env")), .exclude)

        let hiddenOn = IndexingPolicy(homePath: "/Users/test", includeHidden: true)
        XCTAssertEqual(hiddenOn.decision(for: .hiddenFile("/Users/test/.env")), .indexOnly)
        XCTAssertEqual(hiddenOn.decision(for: .directory("/Users/test/Project/.git")), .exclude)
    }
}

private extension FileMetadata {
    static func file(_ path: String) -> FileMetadata {
        fixture(path: path)
    }

    static func directory(_ path: String) -> FileMetadata {
        fixture(path: path, isDirectory: true)
    }

    static func symlink(_ path: String) -> FileMetadata {
        fixture(path: path, isDirectory: true, isSymlink: true)
    }

    static func package(_ path: String) -> FileMetadata {
        fixture(path: path, isDirectory: true, isPackage: true)
    }

    static func hiddenFile(_ path: String) -> FileMetadata {
        fixture(path: path, isHidden: true)
    }

    static func fixture(
        path: String,
        isDirectory: Bool = false,
        isSymlink: Bool = false,
        isPackage: Bool = false,
        isHidden: Bool = false
    ) -> FileMetadata {
        FileMetadata(
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            isDirectory: isDirectory,
            isSymlink: isSymlink,
            isPackage: isPackage,
            isHidden: isHidden,
            sizeBytes: 0,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            deviceID: nil,
            inode: nil
        )
    }
}
