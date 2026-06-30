import XCTest
@testable import MyMacStatsCore

final class DiskSpaceCandidateScannerTests: XCTestCase {
    func testScansCandidateFolderSizesAndSortsLargestFirst() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mymacstats-disk-scanner-\(UUID().uuidString)", isDirectory: true)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: downloads.appendingPathComponent("a.bin"))
        try Data(repeating: 1, count: 131_072).write(to: caches.appendingPathComponent("b.bin"))
        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = DiskSpaceCandidateScanner()
        let candidates = scanner.scan(targets: [
            DiskSpaceCandidateTarget(title: "Downloads", url: downloads),
            DiskSpaceCandidateTarget(title: "Caches", url: caches),
            DiskSpaceCandidateTarget(title: "Missing", url: root.appendingPathComponent("Missing"))
        ])

        XCTAssertEqual(candidates.map(\.title), ["Caches", "Downloads"])
        XCTAssertEqual(candidates.count, 2)
        XCTAssertGreaterThan(candidates[0].sizeBytes, candidates[1].sizeBytes)
        XCTAssertGreaterThan(candidates[1].sizeBytes, 0)
    }

    func testDefaultTargetsAvoidAutomaticTCCPrompts() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let targets = DiskSpaceCandidateScanner.defaultTargets(home: home)

        XCTAssertEqual(targets, [])
    }
}
