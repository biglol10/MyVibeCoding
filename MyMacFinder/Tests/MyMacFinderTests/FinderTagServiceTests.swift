import Foundation
import XCTest
@testable import MyMacFinder

final class FinderTagServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderFinderTagService-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testReadsAndWritesFinderTagsOnAFile() throws {
        let fileURL = tempDirectory.appendingPathComponent("tagged.txt")
        try "tagged".write(to: fileURL, atomically: true, encoding: .utf8)

        let service = FinderTagService()
        try service.setTags([FinderTag("Work"), FinderTag("Red")], for: fileURL)

        XCTAssertEqual(try service.tags(for: fileURL).map(\.name), ["Red", "Work"])
    }

    func testClearsFinderTagsWhenSettingEmptyList() throws {
        let fileURL = tempDirectory.appendingPathComponent("tagged.txt")
        try "tagged".write(to: fileURL, atomically: true, encoding: .utf8)

        let service = FinderTagService()
        try service.setTags([FinderTag("Work")], for: fileURL)
        try service.setTags([], for: fileURL)

        XCTAssertEqual(try service.tags(for: fileURL), [])
    }
}
