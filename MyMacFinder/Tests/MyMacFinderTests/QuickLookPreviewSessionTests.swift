import Foundation
import Quartz
import XCTest
@testable import MyMacFinder

@MainActor
final class QuickLookPreviewSessionTests: XCTestCase {
    func testReleaseRunsExactlyOnce() {
        var releaseCount = 0
        let session = QuickLookPreviewSession(urls: [URL(fileURLWithPath: "/tmp/a")]) {
            releaseCount += 1
        }

        session.release()
        session.release()

        XCTAssertEqual(releaseCount, 1)
    }

    func testReplacingPreviewReleasesPreviousSession() throws {
        var firstReleaseCount = 0
        var secondReleaseCount = 0
        var firstReleaseCountsAtPresentation: [Int] = []
        let service = QuickLookPreviewService(presenter: { _ in
            firstReleaseCountsAtPresentation.append(firstReleaseCount)
        })
        let first = QuickLookPreviewSession(urls: [URL(fileURLWithPath: "/tmp/first")]) {
            firstReleaseCount += 1
        }
        let second = QuickLookPreviewSession(urls: [URL(fileURLWithPath: "/tmp/second")]) {
            secondReleaseCount += 1
        }

        try service.preview(first)
        try service.preview(second)

        XCTAssertEqual(firstReleaseCount, 1)
        XCTAssertEqual(secondReleaseCount, 0)
        XCTAssertEqual(firstReleaseCountsAtPresentation, [0, 1])
    }

    func testEmptyReplacementReleasesPreviousAndIncomingSessionsWithoutRetainingEither() throws {
        var previousReleaseCount = 0
        var emptyReleaseCount = 0
        var presentationCount = 0
        let service = QuickLookPreviewService(presenter: { _ in
            presentationCount += 1
        })
        let previous = QuickLookPreviewSession(urls: [URL(fileURLWithPath: "/tmp/previous")]) {
            previousReleaseCount += 1
        }
        let empty = QuickLookPreviewSession(urls: []) {
            emptyReleaseCount += 1
        }

        try service.preview(previous)
        try service.preview(empty)

        XCTAssertEqual(previousReleaseCount, 1)
        XCTAssertEqual(emptyReleaseCount, 1)
        XCTAssertEqual(presentationCount, 1)
        XCTAssertEqual(service.numberOfPreviewItems(in: nil), 0)
        XCTAssertEqual(previousReleaseCount, 1)
        XCTAssertEqual(emptyReleaseCount, 1)
    }

    func testWindowDelegateCloseCallbackReleasesCurrentSessionExactlyOnceAndClearsPanelOwnership() throws {
        var releaseCount = 0
        let service = QuickLookPreviewService()
        let session = QuickLookPreviewSession(urls: [URL(fileURLWithPath: "/tmp/current")]) {
            releaseCount += 1
        }
        try service.preview(session)
        let panel = try XCTUnwrap(QLPreviewPanel.shared())
        defer {
            panel.dataSource = nil
            panel.delegate = nil
            panel.orderOut(nil)
        }
        let delegate: NSWindowDelegate = service
        let notification = Notification(name: NSWindow.willCloseNotification, object: panel)

        XCTAssertTrue(service.responds(to: #selector(NSWindowDelegate.windowWillClose(_:))))
        delegate.windowWillClose?(notification)
        delegate.windowWillClose?(notification)

        XCTAssertEqual(releaseCount, 1)
        XCTAssertNil(panel.dataSource)
        XCTAssertNil(panel.delegate)
    }

    func testStalePanelCloseDoesNotReleaseReplacementSession() throws {
        var firstReleaseCount = 0
        var replacementReleaseCount = 0
        let service = QuickLookPreviewService()
        let first = QuickLookPreviewSession(urls: [URL(fileURLWithPath: "/tmp/first")]) {
            firstReleaseCount += 1
        }
        let replacement = QuickLookPreviewSession(urls: [URL(fileURLWithPath: "/tmp/replacement")]) {
            replacementReleaseCount += 1
        }
        try service.preview(first)
        try service.preview(replacement)
        let currentPanel = try XCTUnwrap(QLPreviewPanel.shared())
        let stalePanel = QLPreviewPanel()
        defer {
            currentPanel.dataSource = nil
            currentPanel.delegate = nil
            currentPanel.orderOut(nil)
            stalePanel.orderOut(nil)
        }
        let delegate: NSWindowDelegate = service

        delegate.windowWillClose?(
            Notification(name: NSWindow.willCloseNotification, object: stalePanel)
        )

        XCTAssertEqual(firstReleaseCount, 1)
        XCTAssertEqual(replacementReleaseCount, 0)

        delegate.windowWillClose?(
            Notification(name: NSWindow.willCloseNotification, object: currentPanel)
        )
        XCTAssertEqual(replacementReleaseCount, 1)
    }

    func testPresentationFailureDoesNotRetainSession() {
        var releaseCount = 0
        let service = QuickLookPreviewService(presenter: { _ in
            throw ExplorerError.readFailed("Quick Look is unavailable.")
        })
        let session = QuickLookPreviewSession(urls: [URL(fileURLWithPath: "/tmp/failed")]) {
            releaseCount += 1
        }

        XCTAssertThrowsError(try service.preview(session))
        XCTAssertEqual(service.numberOfPreviewItems(in: nil), 0)
        XCTAssertEqual(releaseCount, 0)

        session.release()
        XCTAssertEqual(releaseCount, 1)
    }
}
