import Foundation
import XCTest
@testable import MyMacFinder

final class FilePreviewThumbnailLoaderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderThumbnail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testThumbnailLoaderCanRunOutsideMainActor() async throws {
        let file = tempDirectory.appendingPathComponent("note.txt")
        try "thumbnail".write(to: file, atomically: true, encoding: .utf8)

        _ = await FilePreviewThumbnailLoader.loadPreviewImage(for: file, scale: 1)
    }
}
