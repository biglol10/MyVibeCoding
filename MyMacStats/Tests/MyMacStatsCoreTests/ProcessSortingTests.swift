import XCTest
@testable import MyMacStatsCore

final class ProcessSortingTests: XCTestCase {
    func testFiltersByCaseInsensitiveName() {
        let result = ProcessSorting.filtered(fixtures, searchText: "saf", sortKey: .name, ascending: true)

        XCTAssertEqual(result.map(\.name), ["Safari"])
    }

    func testSortsByCPUDescendingByDefault() {
        let result = ProcessSorting.filtered(fixtures, searchText: "", sortKey: .cpu)

        XCTAssertEqual(result.map(\.name), ["Xcode", "Safari", "Finder"])
    }

    func testSortsByMemoryDescendingByDefault() {
        let result = ProcessSorting.filtered(fixtures, searchText: "", sortKey: .memory)

        XCTAssertEqual(result.map(\.name), ["Safari", "Xcode", "Finder"])
    }

    func testSortsByNameAscendingAndPIDAscending() {
        XCTAssertEqual(ProcessSorting.filtered(fixtures, searchText: "", sortKey: .name, ascending: true).map(\.name), ["Finder", "Safari", "Xcode"])
        XCTAssertEqual(ProcessSorting.filtered(fixtures, searchText: "", sortKey: .pid, ascending: true).map(\.pid), [10, 20, 30])
    }

    private var fixtures: [ProcessMetric] {
        [
            ProcessMetric(pid: 20, name: "Safari", cpuPercent: 12, memoryBytes: 900, path: "/Applications/Safari.app", bundleIdentifier: "com.apple.Safari"),
            ProcessMetric(pid: 10, name: "Finder", cpuPercent: 3, memoryBytes: 200, path: "/System/Library/CoreServices/Finder.app", bundleIdentifier: "com.apple.finder"),
            ProcessMetric(pid: 30, name: "Xcode", cpuPercent: 80, memoryBytes: 700, path: "/Applications/Xcode.app", bundleIdentifier: "com.apple.dt.Xcode")
        ]
    }
}
