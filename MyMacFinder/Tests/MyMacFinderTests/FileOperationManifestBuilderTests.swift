import XCTest
@testable import MyMacFinder

final class FileOperationManifestBuilderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderManifestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testManifestCountsNestedFilesAndBytes() throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4).write(to: folder.appendingPathComponent("a.bin"))
        try Data(repeating: 1, count: 6).write(to: folder.appendingPathComponent("b.bin"))

        let manifest = try FileOperationManifestBuilder().manifest(for: [folder])

        XCTAssertEqual(manifest.totalFileCount, 2)
        XCTAssertEqual(manifest.totalByteCount, 10)
        XCTAssertEqual(manifest.roots, [folder.standardizedFileURL])
    }
}
