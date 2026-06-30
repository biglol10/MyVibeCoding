import XCTest
@testable import MyMacStatsCore

final class MemorySamplerTests: XCTestCase {
    func testUsedMemoryExcludesCachedPagesFromPressureThresholdInput() {
        let snapshot = MemorySampler.snapshot(
            totalBytes: 16 * 1_024 * 1_024,
            pageBytes: 4_096,
            freePages: 128,
            inactivePages: 512,
            speculativePages: 256,
            compressorPages: 64
        )

        XCTAssertEqual(snapshot.freeBytes, 524_288)
        XCTAssertEqual(snapshot.cachedBytes, 3_145_728)
        XCTAssertEqual(snapshot.usedBytes, 13_107_200)
        XCTAssertEqual(snapshot.compressedBytes, 262_144)
    }
}
