import XCTest
import MyMacStatsCore
@testable import MyMacStatsAppSupport

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testSummariesExposeSnapshotSummariesAndSelectedSummary() {
        let viewModel = DashboardViewModel(snapshot: snapshot)

        XCTAssertEqual(viewModel.summaries.map(\.kind), [.cpu, .memory])
        XCTAssertEqual(viewModel.selectedSummary?.kind, .cpu)

        viewModel.select(.memory)

        XCTAssertEqual(viewModel.selectedSummary?.kind, .memory)
    }

    func testCPUAndMemoryScreensSortProcessesByRelevantMetric() {
        let viewModel = DashboardViewModel(snapshot: snapshot)

        XCTAssertEqual(viewModel.displayedProcesses.map(\.name), ["Xcode", "Safari", "Finder"])

        viewModel.select(.memory)

        XCTAssertEqual(viewModel.displayedProcesses.map(\.name), ["Safari", "Xcode", "Finder"])
    }

    func testProcessesScreenUsesSearchAndExplicitSortControls() {
        let viewModel = DashboardViewModel(snapshot: snapshot)
        viewModel.select(.processes)
        viewModel.searchText = "fi"

        XCTAssertEqual(viewModel.displayedProcesses.map(\.name), ["Finder"])

        viewModel.searchText = ""
        viewModel.sortKey = .pid
        viewModel.sortAscending = true

        XCTAssertEqual(viewModel.displayedProcesses.map(\.pid), [10, 20, 30])
    }

    func testRefreshIntervalCanBeChanged() {
        let viewModel = DashboardViewModel(snapshot: snapshot)

        viewModel.refreshInterval = .fiveSeconds

        XCTAssertEqual(viewModel.refreshInterval.seconds, 5)
    }

    private var snapshot: SystemMetricsSnapshot {
        let now = Date(timeIntervalSince1970: 100)
        return SystemMetricsSnapshot(
            summaries: [
                MetricSummary(kind: .cpu, title: "CPU", valueText: "40%", detailText: nil, health: .normal, updatedAt: now),
                MetricSummary(kind: .memory, title: "RAM", valueText: "8 GB / 16 GB", detailText: nil, health: .normal, updatedAt: now)
            ],
            cpu: nil,
            memory: nil,
            disk: nil,
            network: nil,
            battery: nil,
            processes: [
                ProcessMetric(pid: 20, name: "Safari", cpuPercent: 12, memoryBytes: 900, path: "/Applications/Safari.app", bundleIdentifier: "com.apple.Safari"),
                ProcessMetric(pid: 10, name: "Finder", cpuPercent: 3, memoryBytes: 200, path: "/System/Library/CoreServices/Finder.app", bundleIdentifier: "com.apple.finder"),
                ProcessMetric(pid: 30, name: "Xcode", cpuPercent: 80, memoryBytes: 700, path: "/Applications/Xcode.app", bundleIdentifier: "com.apple.dt.Xcode")
            ],
            cpuHistory: [40],
            updatedAt: now
        )
    }
}
