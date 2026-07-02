import XCTest
@testable import MyMacStatsCore

final class NetworkSamplerTests: XCTestCase {
    func testSampleReadsKernelInterfaceCountersWhenAvailable() throws {
        var sampler = NetworkSampler()

        do {
            let snapshot = try sampler.sample()
            XCTAssertNotNil(snapshot.interfaceName)
            XCTAssertGreaterThanOrEqual(snapshot.receivedBytes, 0)
            XCTAssertGreaterThanOrEqual(snapshot.sentBytes, 0)
        } catch SamplerError.unavailable {
            return
        }
    }

    func testSpeedsUseSixtyFourBitCountersPastFourGigabytes() {
        let previous = NetworkCounter(
            name: "en0",
            receivedBytes: UInt64(UInt32.max) - 100,
            sentBytes: UInt64(UInt32.max) - 50,
            sampledAt: Date(timeIntervalSince1970: 100)
        )
        let current = NetworkCounter(
            name: "en0",
            receivedBytes: UInt64(UInt32.max) + 5_000,
            sentBytes: UInt64(UInt32.max) + 1_950,
            sampledAt: Date(timeIntervalSince1970: 102)
        )

        let speeds = NetworkSampler.speeds(previous: previous, current: current)

        XCTAssertEqual(speeds.downloadBytesPerSecond, 2_550)
        XCTAssertEqual(speeds.uploadBytesPerSecond, 1_000)
    }

    func testSpeedsResetWhenActiveInterfaceChanges() {
        let previous = NetworkCounter(name: "en0", receivedBytes: 1_000, sentBytes: 1_000, sampledAt: Date(timeIntervalSince1970: 100))
        let current = NetworkCounter(name: "en1", receivedBytes: 2_000, sentBytes: 2_000, sampledAt: Date(timeIntervalSince1970: 101))

        let speeds = NetworkSampler.speeds(previous: previous, current: current)

        XCTAssertEqual(speeds.downloadBytesPerSecond, 0)
        XCTAssertEqual(speeds.uploadBytesPerSecond, 0)
    }

    func testSelectsInterfaceWithCurrentActivityOverLargestHistoricalCounter() throws {
        let previous = [
            "en0": NetworkCounter(name: "en0", receivedBytes: 9_000_000, sentBytes: 1_000_000, sampledAt: Date(timeIntervalSince1970: 100)),
            "en1": NetworkCounter(name: "en1", receivedBytes: 2_000, sentBytes: 2_000, sampledAt: Date(timeIntervalSince1970: 100))
        ]
        let current = [
            NetworkCounter(name: "en0", receivedBytes: 9_000_000, sentBytes: 1_000_000, sampledAt: Date(timeIntervalSince1970: 101)),
            NetworkCounter(name: "en1", receivedBytes: 8_000, sentBytes: 5_000, sampledAt: Date(timeIntervalSince1970: 101))
        ]

        let selected = try XCTUnwrap(NetworkSampler.selectedCounter(from: current, previousByName: previous))

        XCTAssertEqual(selected.name, "en1")
    }
}
