import XCTest
@testable import MyMacStatsCore

final class DiskSamplerTests: XCTestCase {
    func testVolumeNameFallbackUsesMountPointNameInsteadOfHardCodedMacintoshHD() throws {
        let sampler = DiskSampler(
            path: "/Volumes/ExternalSSD",
            fileSystemAttributesProvider: { _ in
                [
                    .systemSize: NSNumber(value: 1_000),
                    .systemFreeSize: NSNumber(value: 400)
                ]
            },
            volumeNameProvider: { _ in nil },
            ioCounterProvider: { nil },
            dateProvider: { Date(timeIntervalSince1970: 10) }
        )

        let snapshot = try sampler.sample()

        XCTAssertEqual(snapshot.volumeName, "ExternalSSD")
    }

    func testDiskSpeedsUseIOCounterDeltas() throws {
        var samples = [
            DiskIOCounters(bytesRead: 1_000, bytesWritten: 2_000),
            DiskIOCounters(bytesRead: 1_400, bytesWritten: 2_200)
        ]
        var dates = [
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 12)
        ]
        let sampler = DiskSampler(
            path: "/",
            fileSystemAttributesProvider: { _ in
                [
                    .systemSize: NSNumber(value: 1_000),
                    .systemFreeSize: NSNumber(value: 400)
                ]
            },
            volumeNameProvider: { _ in "Data" },
            ioCounterProvider: { samples.removeFirst() },
            dateProvider: { dates.removeFirst() }
        )

        let first = try sampler.sample()
        let second = try sampler.sample()

        XCTAssertNil(first.readBytesPerSecond)
        XCTAssertNil(first.writeBytesPerSecond)
        XCTAssertEqual(second.readBytesPerSecond, 200)
        XCTAssertEqual(second.writeBytesPerSecond, 100)
    }
}
