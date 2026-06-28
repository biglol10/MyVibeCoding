import XCTest
@testable import FlowPilotNativeCore

final class ActivitySessionAccumulatorTests: XCTestCase {
    func testExtendsSameAppWindowSessionWithStableID() {
        var ids = ["s1"]
        let accumulator = ActivitySessionAccumulator(idProvider: { ids.removeFirst() })
        let start = Date(timeIntervalSince1970: 100)

        let first = accumulator.observe(sample(at: start, app: "Codex", title: "Codex"))
        let second = accumulator.observe(sample(at: start.addingTimeInterval(10), app: "Codex", title: "Codex"))

        XCTAssertEqual(first.map(\.id), ["s1"])
        XCTAssertEqual(second.map(\.id), ["s1"])
        XCTAssertEqual(second[0].durationSeconds, 10)
    }

    func testClosesPreviousSessionWhenActiveWindowChanges() {
        var ids = ["s1", "s2"]
        let accumulator = ActivitySessionAccumulator(idProvider: { ids.removeFirst() })
        let start = Date(timeIntervalSince1970: 100)

        _ = accumulator.observe(sample(at: start, app: "Codex", title: "Codex"))
        let records = accumulator.observe(sample(at: start.addingTimeInterval(15), app: "Finder", title: "Finder"))

        XCTAssertEqual(records.map(\.id), ["s1", "s2"])
        XCTAssertEqual(records[0].durationSeconds, 15)
        XCTAssertEqual(records[1].durationSeconds, 1)
    }

    func testMergesGenericFallbackTitleFlapsForSameApp() {
        var ids = ["s1"]
        let accumulator = ActivitySessionAccumulator(idProvider: { ids.removeFirst() })
        let start = Date(timeIntervalSince1970: 100)

        _ = accumulator.observe(sample(at: start, app: "Calendar", title: "Calendar"))
        let records = accumulator.observe(sample(at: start.addingTimeInterval(10), app: "Calendar", title: "Holidays"))

        XCTAssertEqual(records.map(\.id), ["s1"])
        XCTAssertEqual(records[0].windowTitle, "Holidays")
        XCTAssertEqual(records[0].durationSeconds, 10)
    }

    private func sample(at date: Date, app: String, title: String) -> ActivitySample {
        ActivitySample(
            observedAt: date,
            appName: app,
            processName: app,
            windowTitle: title,
            domain: nil,
            isIdle: false
        )
    }
}
