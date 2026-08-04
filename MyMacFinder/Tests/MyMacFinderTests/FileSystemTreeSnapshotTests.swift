import Foundation
import XCTest
@testable import MyMacFinder

final class FileSystemTreeSnapshotTests: XCTestCase {
    func testCaptureRejectsDirectoryMutationDuringEnumeration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MyMacFinderTreeSnapshot-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
                XCTAssertFalse(FileSystemPathIdentity.entryExists(root))
            } catch {
                XCTFail("Failed to remove test directory \(root.path): \(error)")
            }
        }
        let fileManager = MutatingSnapshotFileManager(root: root)

        XCTAssertThrowsError(try FileSystemTreeSnapshot.capture(at: root, fileManager: fileManager)) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed"))
        }
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("late.txt"), encoding: .utf8),
            "late"
        )
    }
}

private final class MutatingSnapshotFileManager: FileManager, @unchecked Sendable {
    private let root: URL
    private var didMutate = false

    init(root: URL) {
        self.root = root.standardizedFileURL
        super.init()
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        let entries = try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
        if url.standardizedFileURL == root, !didMutate {
            didMutate = true
            try "late".write(
                to: root.appendingPathComponent("late.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
        return entries
    }
}
