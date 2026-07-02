import XCTest
@testable import MyMacStatsCore

final class MemorySamplerTests: XCTestCase {
    func testSampleReadsHostStatsPressureAndSwap() throws {
        let snapshot = try MemorySampler().sample()

        XCTAssertGreaterThan(snapshot.totalBytes, 0)
        XCTAssertLessThanOrEqual(snapshot.usedBytes, snapshot.totalBytes)
        XCTAssertNotEqual(snapshot.pressure, .unavailable)
    }

    func testUsedMemoryExcludesCachedPagesFromPressureThresholdInput() {
        let snapshot = MemorySampler.snapshot(
            totalBytes: 16 * 1_024 * 1_024,
            pageBytes: 4_096,
            freePages: 128,
            inactivePages: 512,
            speculativePages: 256,
            compressorPages: 64,
            swapUsedBytes: 123,
            pressure: .warning
        )

        XCTAssertEqual(snapshot.freeBytes, 524_288)
        XCTAssertEqual(snapshot.cachedBytes, 3_145_728)
        XCTAssertEqual(snapshot.usedBytes, 13_107_200)
        XCTAssertEqual(snapshot.compressedBytes, 262_144)
        XCTAssertEqual(snapshot.swapUsedBytes, 123)
        XCTAssertEqual(snapshot.pressure, .warning)
    }

    func testMemoryPressureMappingUsesSysctlLevels() {
        XCTAssertEqual(MemorySampler.pressure(fromRawValue: 0), .normal)
        XCTAssertEqual(MemorySampler.pressure(fromRawValue: 1), .warning)
        XCTAssertEqual(MemorySampler.pressure(fromRawValue: 2), .critical)
    }
}
