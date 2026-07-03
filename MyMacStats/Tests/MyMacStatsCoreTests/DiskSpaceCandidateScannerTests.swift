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

    func testSlowDuCommandTimesOutAndFallsBackToLimitedScan() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mymacstats-disk-scanner-timeout-\(UUID().uuidString)", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_096).write(to: caches.appendingPathComponent("item.bin"))
        let slowDu = root.appendingPathComponent("slow-du.sh")
        try """
        #!/bin/sh
        sleep 5
        """.write(to: slowDu, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: slowDu.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = DiskSpaceCandidateScanner(
            duExecutableURL: slowDu,
            duTimeout: 0.05
        )
        let start = Date()
        let candidates = scanner.scan(targets: [
            DiskSpaceCandidateTarget(title: "Caches", url: caches)
        ])
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 1)
        XCTAssertEqual(candidates.map(\.title), ["Caches"])
        XCTAssertGreaterThan(candidates[0].sizeBytes, 0)
    }

    func testDefaultTargetsUseNonTCCLibraryFolders() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let targets = DiskSpaceCandidateScanner.defaultTargets(home: home)

        XCTAssertEqual(targets.map(\.title), ["Caches", "Xcode DerivedData"])
        XCTAssertEqual(targets.map(\.url.path), [
            "/Users/example/Library/Caches",
            "/Users/example/Library/Developer/Xcode/DerivedData"
        ])
        XCTAssertFalse(targets.contains { $0.url.path.contains("/Downloads") })
        XCTAssertFalse(targets.contains { $0.url.path.contains("/Documents") })
        XCTAssertFalse(targets.contains { $0.url.path.contains("/Desktop") })
    }
}
