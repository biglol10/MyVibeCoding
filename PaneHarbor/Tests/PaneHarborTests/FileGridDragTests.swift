import AppKit
import XCTest
@testable import PaneHarbor

@MainActor
final class FileGridDragTests: XCTestCase {
    func testGridDropLoadsAllNativeFileURLsWithoutChangingPercentOrUnicode() async {
        let urls = ["한글 공백 %20 + #.txt", "second.txt"].map { URL(fileURLWithPath: "/Users/Shared/\($0)") }
        let loaded = await FileGridDropDelegate.loadFileURLs(from: urls.map { NSItemProvider(object: $0 as NSURL) })
        XCTAssertEqual(loaded, urls)
        let mixed = await FileGridDropDelegate.loadFileURLs(from: [
            NSItemProvider(object: urls[0] as NSURL), NSItemProvider(object: URL(string: "https://example.com")! as NSURL)
        ])
        XCTAssertNil(mixed, "An invalid item must reject the whole batch")
    }
    func testNativeGridDragWritesEverySelectedURLIncludingUnicodeAndFolder() throws {
        let urls = ["alpha.txt", "한글 공백 % + #.txt", "폴더"].map {
            URL(fileURLWithPath: "/Users/Shared/PaneHarbor QA/\($0)")
        }
        let view = FileGridDragView(frame: NSRect(x: 0, y: 0, width: 130, height: 132))
        view.dragURLs = { urls }
        let items = view.makeDraggingItems()
        XCTAssertEqual(items.count, 3)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        XCTAssertTrue(board.writeObjects(try items.map { try XCTUnwrap($0.item as? NSURL) }))
        XCTAssertEqual(FileDropPasteboardReader.fileURLs(from: board), urls)
    }

    func testGridDragRejectsNonFileURLsAndDeduplicates() {
        let url = URL(fileURLWithPath: "/Users/Shared/한글 공백.txt")
        let view = FileGridDragView()
        view.dragURLs = { [url, url, URL(string: "https://example.com/file.txt")!] }
        XCTAssertEqual(view.makeDraggingItems().count, 1)
        view.enabled = false
        XCTAssertTrue(view.makeDraggingItems().isEmpty)
    }

    func testMouseUpClicksExactlyOnceAndIgnoresStaleEvent() throws {
        let view = FileGridDragView()
        var clicked = 0
        view.onClick = { _, _ in clicked += 1 }
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero,
            modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 0))
        view.mouseDown(with: down)
        view.mouseUp(with: up)
        XCTAssertEqual(clicked, 1)
        view.mouseUp(with: up)
        XCTAssertEqual(clicked, 1, "A stale mouse-up must not click another tile")
    }
}
