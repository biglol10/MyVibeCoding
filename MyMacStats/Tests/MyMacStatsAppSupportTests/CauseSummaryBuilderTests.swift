import XCTest
import MyMacStatsCore
@testable import MyMacStatsAppSupport

final class CauseSummaryBuilderTests: XCTestCase {
    func testBuildsRAMCauseFromTopMemoryGroupsWhenHealthIsBad() {
        let now = Date(timeIntervalSince1970: 100)
        let snapshot = SystemMetricsSnapshot(
            summaries: [
                MetricSummary(kind: .memory, title: "RAM", valueText: "15G / 16G", detailText: "Free 500 MB", health: .critical, updatedAt: now)
            ],
            cpu: nil,
            memory: MemorySnapshot(totalBytes: gib(16), usedBytes: gib(15), freeBytes: 500, compressedBytes: nil, cachedBytes: nil, swapUsedBytes: gib(2), pressure: .critical, sampledAt: now),
            disk: nil,
            network: nil,
            battery: nil,
            processes: [
                ProcessMetric(pid: 1, name: "Chrome", cpuPercent: 2, memoryBytes: gib(2), path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", bundleIdentifier: "com.google.Chrome"),
                ProcessMetric(pid: 2, name: "Chrome Helper", cpuPercent: 1, memoryBytes: gib(1), path: "/Applications/Google Chrome.app/Contents/Frameworks/Chrome Helper.app/Contents/MacOS/Chrome Helper", bundleIdentifier: "com.google.Chrome.helper"),
                ProcessMetric(pid: 3, name: "Code", cpuPercent: 1, memoryBytes: gib(1), path: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron", bundleIdentifier: "com.microsoft.VSCode")
            ],
            cpuHistory: [],
            updatedAt: now
        )

        let summary = CauseSummaryBuilder.summary(for: .memory, snapshot: snapshot)

        XCTAssertEqual(summary?.title, "RAM critical")
        XCTAssertEqual(summary?.message, "Google Chrome is using 3 GB. Swap is 2 GB.")
        XCTAssertEqual(summary?.health, .critical)
    }

    func testBuildsCPUCauseFromTopCPUGroup() {
        let now = Date(timeIntervalSince1970: 100)
        let snapshot = SystemMetricsSnapshot(
            summaries: [
                MetricSummary(kind: .cpu, title: "CPU", valueText: "91%", detailText: nil, health: .critical, updatedAt: now)
            ],
            cpu: CPUSnapshot(totalUsagePercent: 91, userPercent: 70, systemPercent: 21, idlePercent: 9, sampledAt: now),
            memory: nil,
            disk: nil,
            network: nil,
            battery: nil,
            processes: [
                ProcessMetric(pid: 1, name: "Xcode", cpuPercent: 44, memoryBytes: 200, path: "/Applications/Xcode.app/Contents/MacOS/Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
                ProcessMetric(pid: 2, name: "Safari", cpuPercent: 10, memoryBytes: 100, path: "/Applications/Safari.app/Contents/MacOS/Safari", bundleIdentifier: "com.apple.Safari")
            ],
            cpuHistory: [91],
            updatedAt: now
        )

        let summary = CauseSummaryBuilder.summary(for: .cpu, snapshot: snapshot)

        XCTAssertEqual(summary?.title, "CPU critical")
        XCTAssertEqual(summary?.message, "Xcode is using 44% CPU.")
    }

    func testDoesNotBuildSummaryForNormalHealth() {
        let now = Date(timeIntervalSince1970: 100)
        let snapshot = SystemMetricsSnapshot(
            summaries: [
                MetricSummary(kind: .cpu, title: "CPU", valueText: "20%", detailText: nil, health: .normal, updatedAt: now)
            ],
            cpu: nil,
            memory: nil,
            disk: nil,
            network: nil,
            battery: nil,
            processes: [],
            cpuHistory: [],
            updatedAt: now
        )

        XCTAssertNil(CauseSummaryBuilder.summary(for: .cpu, snapshot: snapshot))
    }

    private func gib(_ value: UInt64) -> UInt64 {
        value * 1_024 * 1_024 * 1_024
    }
}
