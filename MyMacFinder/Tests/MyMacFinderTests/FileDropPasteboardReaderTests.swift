import AppKit
import XCTest
@testable import MyMacFinder

final class FileDropPasteboardReaderTests: XCTestCase {
    func testReadsFileURLsFromPasteboardObjects() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MyMacFinderPasteboard-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let url = URL(fileURLWithPath: "/tmp/MyMacFinderExternalDrop/object.txt")

        XCTAssertTrue(pasteboard.writeObjects([url as NSURL]))

        XCTAssertEqual(FileDropPasteboardReader.fileURLs(from: pasteboard), [url.standardizedFileURL])
    }

    func testReadsLegacyFinderFilenameList() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MyMacFinderPasteboard-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let url = URL(fileURLWithPath: "/tmp/MyMacFinderExternalDrop/legacy.txt")
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

        pasteboard.setPropertyList([url.path], forType: filenamesType)

        XCTAssertEqual(FileDropPasteboardReader.fileURLs(from: pasteboard), [url.standardizedFileURL])
    }

    func testAcceptedTypesIncludeModernAndLegacyFinderTypes() {
        XCTAssertTrue(FileDropPasteboardReader.acceptedTypes.contains(.fileURL))
        XCTAssertTrue(FileDropPasteboardReader.acceptedTypes.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")))
    }
}
