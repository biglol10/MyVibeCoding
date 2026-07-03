import XCTest
@testable import MyMacCleanCore

final class LargeFileScannerTests: XCTestCase {
    func testScannerReturnsOnlyFilesAtOrAboveMinimumSize() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "large-files-threshold")
        let smallFile = root.appendingPathComponent("small.mov")
        let largeFile = root.appendingPathComponent("large.mov")
        try Data(repeating: 1, count: 10).write(to: smallFile)
        try Data(repeating: 1, count: 1_024).write(to: largeFile)

        let results = try await LargeFileScanner(
            roots: [root],
            minimumSize: 1_000
        ).scan()

        XCTAssertEqual(results.map(\.url), [largeFile])
        XCTAssertEqual(results.first?.size, 1_024)
        XCTAssertEqual(results.first?.kind, .video)
        XCTAssertFalse(results.first?.defaultSelected ?? true)
    }

    func testScannerSkipsAppBundlesAndPackageContents() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "large-files-packages")
        let appBundle = root.appendingPathComponent("Heavy.app", isDirectory: true)
        let appPayload = appBundle.appendingPathComponent("Contents/Resources/payload.bin")
        let normalFile = root.appendingPathComponent("export.zip")
        try FileManager.default.createDirectory(at: appPayload.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2_000).write(to: appPayload)
        try Data(repeating: 1, count: 1_500).write(to: normalFile)

        let results = try await LargeFileScanner(
            roots: [root],
            minimumSize: 1_000
        ).scan()

        XCTAssertEqual(results.map(\.url), [normalFile])
    }

    func testScannerCanLimitScanToRootLevelFiles() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "large-files-nonrecursive")
        let nestedFolder = root.appendingPathComponent("Project", isDirectory: true)
        let nestedFile = nestedFolder.appendingPathComponent("nested.mov")
        let directFile = root.appendingPathComponent("direct.mov")
        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2_000).write(to: nestedFile)
        try Data(repeating: 1, count: 1_500).write(to: directFile)

        let results = try await LargeFileScanner(
            roots: [root],
            minimumSize: 1_000,
            recursive: false
        ).scan()

        XCTAssertEqual(results.map(\.url), [directFile])
    }

    func testScannerSkipsSystemRootsEvenWhenProvidedDirectly() async throws {
        let results = try await LargeFileScanner(
            roots: [URL(fileURLWithPath: "/System", isDirectory: true)],
            minimumSize: 1
        ).scan()

        XCTAssertTrue(results.isEmpty)
    }

    func testScannerSortsBySizeDescendingByDefault() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "large-files-sort")
        let medium = root.appendingPathComponent("medium.zip")
        let largest = root.appendingPathComponent("largest.dmg")
        try Data(repeating: 1, count: 1_500).write(to: medium)
        try Data(repeating: 1, count: 3_000).write(to: largest)

        let results = try await LargeFileScanner(
            roots: [root],
            minimumSize: 1_000
        ).scan()

        XCTAssertEqual(results.map(\.url), [largest, medium])
    }
}
