import XCTest
@testable import MyMacFinder

final class FilePreviewPolicyTests: XCTestCase {
    func testOffModeDisablesInlinePreviewBeforeReadingFile() {
        XCTAssertEqual(
            FilePreviewPolicy.contentAvailability(mode: .off),
            .unavailable(message: "Preview disabled in Settings.")
        )
    }

    func testTextOnlyModeSkipsVisualThumbnailGeneration() {
        let image = makeEntry(name: "photo.jpg", extension: "jpg", size: 1_024)

        XCTAssertEqual(
            FilePreviewPolicy.thumbnailAvailability(for: image, mode: .textOnly),
            .unavailable(message: "Visual previews disabled. Use Quick Look to preview this file.")
        )
    }

    func testSmartModeSkipsLargeVisualFiles() {
        let movie = makeEntry(name: "movie.mov", extension: "mov", size: 51)

        XCTAssertEqual(
            FilePreviewPolicy.thumbnailAvailability(for: movie, mode: .smart, largeFileLimit: 50),
            .unavailable(message: "Large file preview skipped. Use Quick Look to preview this file.")
        )
    }

    func testSmartModeAllowsSmallVisualFiles() {
        let image = makeEntry(name: "photo.jpg", extension: "jpg", size: 49)

        XCTAssertEqual(
            FilePreviewPolicy.thumbnailAvailability(for: image, mode: .smart, largeFileLimit: 50),
            .available
        )
    }

    private func makeEntry(name: String, extension fileExtension: String, size: Int64?) -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            kind: .file,
            typeDescription: "File",
            fileExtension: fileExtension,
            size: size,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )
    }
}
