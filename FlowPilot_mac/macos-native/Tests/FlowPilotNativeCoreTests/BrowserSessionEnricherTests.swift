import XCTest
@testable import FlowPilotNativeCore

final class BrowserSessionEnricherTests: XCTestCase {
    func testEnrichesChromeSessionWithMatchingRecentTabDomain() {
        let end = Date(timeIntervalSince1970: 100)
        let session = browserSession(end: end, title: "ChatGPT - Google Chrome")
        let event = BrowserEventRecord(
            id: "event-1",
            occurredAt: end.addingTimeInterval(-10),
            domain: "chatgpt.com",
            url: nil,
            title: "ChatGPT"
        )

        let enriched = BrowserSessionEnricher.enrich(session: session, events: [event])

        XCTAssertEqual(enriched.domain, "chatgpt.com")
    }

    func testFallsBackToVeryRecentBrowserEventWithoutTitleMatch() {
        let end = Date(timeIntervalSince1970: 100)
        let session = browserSession(end: end, title: "Untitled - Google Chrome")
        let event = BrowserEventRecord(
            id: "event-1",
            occurredAt: end.addingTimeInterval(-5),
            domain: "github.com",
            url: nil,
            title: "GitHub"
        )

        let enriched = BrowserSessionEnricher.enrich(session: session, events: [event])

        XCTAssertEqual(enriched.domain, "github.com")
    }

    func testDoesNotEnrichNonBrowserApp() {
        let end = Date(timeIntervalSince1970: 100)
        let session = ActivitySessionRecord(
            id: "session-1",
            startedAt: end.addingTimeInterval(-10),
            endedAt: end,
            durationSeconds: 10,
            appName: "Codex",
            processName: "Codex",
            windowTitle: "ChatGPT",
            domain: nil,
            url: nil,
            isIdle: false
        )
        let event = BrowserEventRecord(
            id: "event-1",
            occurredAt: end.addingTimeInterval(-5),
            domain: "chatgpt.com",
            url: nil,
            title: "ChatGPT"
        )

        let enriched = BrowserSessionEnricher.enrich(session: session, events: [event])

        XCTAssertNil(enriched.domain)
    }

    private func browserSession(end: Date, title: String) -> ActivitySessionRecord {
        ActivitySessionRecord(
            id: "session-1",
            startedAt: end.addingTimeInterval(-10),
            endedAt: end,
            durationSeconds: 10,
            appName: "Google Chrome",
            processName: "Google Chrome",
            windowTitle: title,
            domain: nil,
            url: nil,
            isIdle: false
        )
    }
}
