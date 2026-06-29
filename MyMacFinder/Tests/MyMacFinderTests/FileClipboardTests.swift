import Foundation
import XCTest
@testable import MyMacFinder

final class FileClipboardTests: XCTestCase {
    func testClipboardReportsEmptyWhenNoURLs() {
        let clipboard = FileClipboard(urls: [], mode: .copy)

        XCTAssertTrue(clipboard.isEmpty)
    }

    func testClipboardStoresURLsAndMode() {
        let url = URL(fileURLWithPath: "/tmp/file.txt")
        let clipboard = FileClipboard(urls: [url], mode: .move)

        XCTAssertFalse(clipboard.isEmpty)
        XCTAssertEqual(clipboard.urls, [url])
        XCTAssertEqual(clipboard.mode, .move)
    }
}
