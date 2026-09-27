import XCTest
@testable import MyMacStatsCore

final class ProcessGroupingTests: XCTestCase {
    func testApplicationIdentityNormalizesPathComponentsWithoutMergingCopies() {
        let paths = ["/Applications/Example.app/./Contents/MacOS/Example", "/Applications/Unused/../Example.app/Contents/MacOS/Helper"]
        let processes = paths.enumerated().map { index, path in
            ProcessMetric(pid: Int32(10 + index), name: "worker", cpuPercent: 1, memoryBytes: 10, path: path, bundleIdentifier: nil)
        }
        let groups = ProcessGrouping.groups(processes, searchText: "", sortKey: .cpu)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, "app:/Applications/Example.app")
        XCTAssertEqual(groups[0].processes.count, 2)
    }

    func testSameExecutableAndNameDoNotMergeIndependentProcesses() {
        let processes = [10, 11].map { pid in
            ProcessMetric(pid: Int32(pid), name: "node", cpuPercent: 1, memoryBytes: 10, path: "/opt/homebrew/bin/node", bundleIdentifier: "shared.identifier")
        }
        let groups = ProcessGrouping.groups(processes, searchText: "", sortKey: .cpu)
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.processes.count == 1 && !$0.isApplicationTarget })
    }

    func testSameNamedAppCopiesRemainSeparate() {
        let processes = ["/Applications/Example.app", "/Users/example/Test/Example.app"].enumerated().map { index, path in
            ProcessMetric(pid: Int32(10 + index), name: "Example", cpuPercent: 1, memoryBytes: 10, path: path + "/Contents/MacOS/Example", bundleIdentifier: "com.example.app")
        }
        let groups = ProcessGrouping.groups(processes, searchText: "", sortKey: .cpu)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.id)).count, 2)
    }

    func testGroupsProcessesByOwningApplicationBundle() {
        let processes = [
            ProcessMetric(
                pid: 10,
                name: "Google Chrome",
                cpuPercent: 12,
                memoryBytes: 500,
                path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                bundleIdentifier: "com.google.Chrome"
            ),
            ProcessMetric(
                pid: 11,
                name: "Google Chrome Helper (Renderer)",
                cpuPercent: 8,
                memoryBytes: 700,
                path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
                bundleIdentifier: "com.google.Chrome.helper.renderer"
            ),
            ProcessMetric(
                pid: 12,
                name: "Code Helper (Plugin)",
                cpuPercent: 4,
                memoryBytes: 300,
                path: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)",
                bundleIdentifier: "com.microsoft.VSCode.helper"
            )
        ]

        let groups = ProcessGrouping.groups(processes, searchText: "", sortKey: .memory)

        XCTAssertEqual(groups.map(\.name), ["Google Chrome", "Visual Studio Code"])
        XCTAssertEqual(groups[0].processes.map(\.pid), [11, 10])
        XCTAssertEqual(groups[0].cpuPercent, 20)
        XCTAssertEqual(groups[0].memoryBytes, 1_200)
    }

    func testFiltersGroupsByAppNameProcessNameOrPID() {
        let processes = [
            ProcessMetric(pid: 20, name: "Safari", cpuPercent: 2, memoryBytes: 100, path: "/Applications/Safari.app/Contents/MacOS/Safari", bundleIdentifier: "com.apple.Safari"),
            ProcessMetric(pid: 30, name: "Notes", cpuPercent: 1, memoryBytes: 200, path: "/System/Applications/Notes.app/Contents/MacOS/Notes", bundleIdentifier: "com.apple.Notes")
        ]

        XCTAssertEqual(ProcessGrouping.groups(processes, searchText: "safari", sortKey: .cpu).map(\.name), ["Safari"])
        XCTAssertEqual(ProcessGrouping.groups(processes, searchText: "30", sortKey: .cpu).map(\.name), ["Notes"])
    }

    func testDescendingResourceGroupSortsUseNameAsStableTieBreaker() {
        let processes = [
            ProcessMetric(pid: 30, name: "Xcode", cpuPercent: 50, memoryBytes: 900, path: "/Applications/Xcode.app/Contents/MacOS/Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
            ProcessMetric(pid: 20, name: "Safari", cpuPercent: 50, memoryBytes: 900, path: "/Applications/Safari.app/Contents/MacOS/Safari", bundleIdentifier: "com.apple.Safari")
        ]

        let groups = ProcessGrouping.groups(processes, searchText: "", sortKey: .cpu)

        XCTAssertEqual(groups.map(\.name), ["Safari", "Xcode"])
    }
}
