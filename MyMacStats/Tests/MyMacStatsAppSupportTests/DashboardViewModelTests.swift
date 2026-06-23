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

    func testProcessBackedScreensExposeSearchAndSortControls() {
        let viewModel = DashboardViewModel(snapshot: snapshot)

        XCTAssertTrue(viewModel.showsProcessControls)

        viewModel.select(.memory)
        XCTAssertTrue(viewModel.showsProcessControls)

        viewModel.select(.processes)
        XCTAssertTrue(viewModel.showsProcessControls)

        viewModel.select(.disk)
        XCTAssertFalse(viewModel.showsProcessControls)
    }

    func testCPUAndMemoryScreensUseVisibleSortControls() {
        let viewModel = DashboardViewModel(snapshot: snapshot)

        viewModel.sortKey = .name
        viewModel.sortAscending = true

        XCTAssertEqual(viewModel.displayedProcesses.map(\.name), ["Finder", "Safari", "Xcode"])

        viewModel.select(.memory)
        viewModel.sortKey = .pid
        viewModel.sortAscending = true

        XCTAssertEqual(viewModel.displayedProcesses.map(\.pid), [10, 20, 30])
    }

    func testEachProcessBackedScreenKeepsItsOwnSortPreference() {
        let viewModel = DashboardViewModel(snapshot: snapshot)

        XCTAssertEqual(viewModel.sortKey, .cpu)
        XCTAssertFalse(viewModel.sortAscending)

        viewModel.select(.memory)

        XCTAssertEqual(viewModel.sortKey, .memory)
        XCTAssertFalse(viewModel.sortAscending)

        viewModel.sortKey = .pid
        viewModel.sortAscending = true

        viewModel.select(.cpu)
        XCTAssertEqual(viewModel.sortKey, .cpu)
        XCTAssertFalse(viewModel.sortAscending)

        viewModel.select(.memory)
        XCTAssertEqual(viewModel.sortKey, .pid)
        XCTAssertTrue(viewModel.sortAscending)
    }

    func testProcessesScreenUsesSearchAndExplicitSortControls() {
        let viewModel = DashboardViewModel(snapshot: snapshot)
        viewModel.select(.processes)
        viewModel.searchText = "fi"

        XCTAssertEqual(viewModel.displayedProcesses.map(\.name), ["Finder"])
        XCTAssertEqual(viewModel.displayedProcessGroups.map(\.name), ["Finder"])

        viewModel.searchText = ""
        viewModel.sortKey = .pid
        viewModel.sortAscending = true

        XCTAssertEqual(viewModel.displayedProcesses.map(\.pid), [10, 20, 30])
        XCTAssertEqual(viewModel.displayedProcessGroups.flatMap { $0.processes.map(\.pid) }, [10, 20, 30])
    }

    func testSelectedProcessGroupFollowsSelectedProcess() {
        let viewModel = DashboardViewModel(snapshot: groupedSnapshot)

        XCTAssertEqual(viewModel.displayedProcessGroups.map(\.name), ["Safari", "Visual Studio Code"])
        XCTAssertEqual(viewModel.selectedProcessGroup?.name, "Safari")

        viewModel.selectProcess(pid: 41)

        XCTAssertEqual(viewModel.selectedProcessGroup?.name, "Visual Studio Code")
        XCTAssertEqual(viewModel.selectedProcessGroup?.processes.map(\.pid), [41, 40])
    }

    func testSelectedProcessDefaultsToLeadProcessInsideSelectedGroup() {
        let now = Date(timeIntervalSince1970: 250)
        let viewModel = DashboardViewModel(
            snapshot: SystemMetricsSnapshot(
                summaries: [
                    MetricSummary(kind: .memory, title: "RAM", valueText: "15 GB / 16 GB", detailText: nil, health: .critical, updatedAt: now)
                ],
                cpu: nil,
                memory: nil,
                disk: nil,
                network: nil,
                battery: nil,
                processes: [
                    ProcessMetric(pid: 60, name: "Chrome Helper", cpuPercent: 0, memoryBytes: 900, path: "/Applications/Google Chrome.app/Contents/Frameworks/Chrome Helper.app", bundleIdentifier: "com.google.Chrome.helper"),
                    ProcessMetric(pid: 61, name: "Google Chrome", cpuPercent: 0, memoryBytes: 800, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", bundleIdentifier: "com.google.Chrome"),
                    ProcessMetric(pid: 70, name: "mds_stores", cpuPercent: 0, memoryBytes: 1_200, path: "/System/Library/Frameworks/CoreServices.framework/mds_stores", bundleIdentifier: nil)
                ],
                cpuHistory: [],
                updatedAt: now
            )
        )

        viewModel.select(.memory)

        XCTAssertEqual(viewModel.selectedProcessGroup?.name, "Google Chrome")
        XCTAssertEqual(viewModel.selectedProcess?.pid, 60)
    }

    func testRefreshIntervalCanBeChanged() {
        let viewModel = DashboardViewModel(snapshot: snapshot)

        viewModel.refreshInterval = .fiveSeconds

        XCTAssertEqual(viewModel.refreshInterval.seconds, 5)
    }

    func testCPUHistoryRangeFiltersOneMinuteOrFiveMinutes() {
        let now = Date(timeIntervalSince1970: 500)
        let viewModel = DashboardViewModel(
            snapshot: SystemMetricsSnapshot(
                summaries: [],
                cpu: nil,
                memory: nil,
                disk: nil,
                network: nil,
                battery: nil,
                processes: [],
                cpuHistory: [1, 2, 3],
                cpuHistorySamples: [
                    MetricHistorySample(date: Date(timeIntervalSince1970: 100), value: 1),
                    MetricHistorySample(date: Date(timeIntervalSince1970: 450), value: 2),
                    MetricHistorySample(date: Date(timeIntervalSince1970: 490), value: 3)
                ],
                updatedAt: now
            )
        )

        viewModel.historyRange = .oneMinute
        XCTAssertEqual(viewModel.displayedCPUHistory, [2, 3])

        viewModel.historyRange = .fiveMinutes
        XCTAssertEqual(viewModel.displayedCPUHistory, [2, 3])
    }

    func testTerminationAvailabilityAndMessages() {
        var sent: [(Int32, Int32)] = []
        let viewModel = DashboardViewModel(
            snapshot: snapshot,
            terminator: ProcessTerminator(
                currentProcessID: 99,
                signalSender: { pid, signal in
                    sent.append((pid, signal))
                    return 0
                },
                errnoProvider: { 0 }
            )
        )

        viewModel.selectProcess(pid: 20)
        XCTAssertTrue(viewModel.selectedProcessTerminationAvailability.isAllowed)

        viewModel.requestTermination(for: viewModel.selectedProcess!)
        XCTAssertEqual(viewModel.pendingTerminationProcess?.pid, 20)

        viewModel.confirmPendingTermination()

        XCTAssertNil(viewModel.pendingTerminationProcess)
        XCTAssertEqual(viewModel.terminationMessage, "Termination requested for Safari.")
        XCTAssertEqual(viewModel.selectedProcessTerminationMessage, "Termination requested for Safari.")
        XCTAssertEqual(sent.last?.1, SIGTERM)
        XCTAssertTrue(viewModel.selectedProcessCanForceQuit)

        viewModel.requestForceTermination(for: viewModel.selectedProcess!)
        XCTAssertEqual(viewModel.pendingTerminationMode, .forceQuit)

        viewModel.confirmPendingTermination()

        XCTAssertEqual(viewModel.terminationMessage, "Force quit requested for Safari.")
        XCTAssertEqual(sent.last?.1, SIGKILL)
        XCTAssertFalse(viewModel.selectedProcessCanForceQuit)

        viewModel.selectProcess(pid: 30)

        XCTAssertNil(viewModel.selectedProcessTerminationMessage)
    }

    func testProtectedTerminationIsDisabled() {
        let now = Date(timeIntervalSince1970: 100)
        let viewModel = DashboardViewModel(
            snapshot: SystemMetricsSnapshot(
                summaries: [],
                cpu: nil,
                memory: nil,
                disk: nil,
                network: nil,
                battery: nil,
                processes: [
                    ProcessMetric(pid: 1, name: "launchd", cpuPercent: 0, memoryBytes: 0, path: "/sbin/launchd", bundleIdentifier: nil)
                ],
                cpuHistory: [],
                updatedAt: now
            ),
            terminator: ProcessTerminator(currentProcessID: 99)
        )

        XCTAssertFalse(viewModel.selectedProcessTerminationAvailability.isAllowed)
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

    private var groupedSnapshot: SystemMetricsSnapshot {
        let now = Date(timeIntervalSince1970: 200)
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
                ProcessMetric(pid: 40, name: "Code", cpuPercent: 3, memoryBytes: 400, path: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron", bundleIdentifier: "com.microsoft.VSCode"),
                ProcessMetric(pid: 41, name: "Code Helper (Renderer)", cpuPercent: 30, memoryBytes: 900, path: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Renderer).app/Contents/MacOS/Code Helper (Renderer)", bundleIdentifier: "com.microsoft.VSCode.helper"),
                ProcessMetric(pid: 50, name: "Safari", cpuPercent: 35, memoryBytes: 500, path: "/Applications/Safari.app/Contents/MacOS/Safari", bundleIdentifier: "com.apple.Safari")
            ],
            cpuHistory: [40],
            updatedAt: now
        )
    }
}
