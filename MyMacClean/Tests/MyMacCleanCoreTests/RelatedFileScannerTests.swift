import XCTest
@testable import MyMacCleanCore

final class RelatedFileScannerTests: XCTestCase {
    func testScansKnownLibraryLocationsAndMarksProtectedMatches() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "scanner-home")
        let app = InstalledApp(
            displayName: "Figma",
            bundleIdentifier: "com.figma.Desktop",
            version: nil,
            executableName: "Figma",
            bundleURL: home.appendingPathComponent("Applications/Figma.app"),
            iconIdentifier: nil,
            bundleSize: 10,
            lastOpenedAt: nil
        )
        let support = home.appendingPathComponent("Library/Application Support/Figma", isDirectory: true)
        let cache = home.appendingPathComponent("Library/Caches/com.figma.Desktop", isDirectory: true)
        let document = home.appendingPathComponent("Documents/Figma Export.fig")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: document.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4).write(to: support.appendingPathComponent("state.json"))
        try Data(repeating: 1, count: 5).write(to: cache.appendingPathComponent("cache.bin"))
        try Data(repeating: 1, count: 6).write(to: document)

        let scanner = RelatedFileScanner(homeDirectory: home, extraScanRoots: [home.appendingPathComponent("Documents")])
        let candidates = try await scanner.scanRelatedFiles(for: app)
        let summary = candidates
            .map { "\($0.url.path)|\($0.kind.rawValue)|protected=\($0.isProtected)" }
            .joined(separator: "\n")

        XCTAssertTrue(candidates.contains { $0.url == support && $0.kind == .applicationSupport && !$0.isProtected }, summary)
        XCTAssertTrue(candidates.contains { $0.url == cache && $0.kind == .cache && !$0.isProtected }, summary)
        XCTAssertTrue(candidates.contains { $0.url == document && $0.isProtected }, summary)
    }

    func testScansNestedMacOSSupportLocations() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "scanner-nested-home")
        let app = InstalledApp(
            displayName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            version: nil,
            executableName: "Cursor",
            bundleURL: home.appendingPathComponent("Applications/Cursor.app"),
            iconIdentifier: nil,
            bundleSize: 10,
            lastOpenedAt: nil
        )
        let nestedSupportCache = home.appendingPathComponent("Library/Application Support/Caches/cursor-updater", isDirectory: true)
        let byHostPreference = home.appendingPathComponent("Library/Preferences/ByHost/com.todesktop.230313mzl4w4u92.ShipIt.HOST.plist")
        try FileManager.default.createDirectory(at: nestedSupportCache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: byHostPreference.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4).write(to: nestedSupportCache.appendingPathComponent("update.bin"))
        try Data(repeating: 1, count: 5).write(to: byHostPreference)

        let scanner = RelatedFileScanner(homeDirectory: home)
        let candidates = try await scanner.scanRelatedFiles(for: app)
        let summary = candidates
            .map { "\($0.url.path)|\($0.kind.rawValue)|\($0.matchReason)" }
            .joined(separator: "\n")

        XCTAssertTrue(candidates.contains { $0.url == nestedSupportCache && $0.kind == .cache }, summary)
        XCTAssertTrue(candidates.contains { $0.url == byHostPreference && $0.kind == .preferences }, summary)
    }

    func testScannerAttachesEvidenceAndSafetyToCandidates() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "scanner-evidence-home")
        let app = InstalledApp(
            displayName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            version: nil,
            executableName: "Cursor",
            bundleURL: home.appendingPathComponent("Applications/Cursor.app"),
            iconIdentifier: nil,
            bundleSize: 10,
            lastOpenedAt: nil
        )
        let cache = home.appendingPathComponent("Library/Caches/com.todesktop.230313mzl4w4u92", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        let candidates = try await RelatedFileScanner(homeDirectory: home).scanRelatedFiles(for: app)
        let scanned = try XCTUnwrap(candidates.first { $0.url == cache })

        XCTAssertEqual(scanned.safety, .safe)
        XCTAssertEqual(scanned.evidence.first?.type, .bundleIdentifier)
        XCTAssertEqual(scanned.evidence.first?.matchedValue, "com.todesktop.230313mzl4w4u92")
    }
}
