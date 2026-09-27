import XCTest
@testable import MyMacCleanCore

final class AuditSafetyRegressionTests: XCTestCase {
    private func makeApp(name: String, bundleID: String) -> InstalledApp {
        InstalledApp(displayName: name, bundleIdentifier: bundleID, version: nil, executableName: name, bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"), iconIdentifier: nil, bundleSize: 1, lastOpenedAt: nil)
    }

    func testCompactNameCannotMatchInsideUnrelatedWord() {
        let app = makeApp(name: "North Star", bundleID: "com.audit.northstar")
        let match = CandidateMatcher().match(url: URL(fileURLWithPath: "/Users/me/Library/Application Support/com.vendor.northstarfish"), app: app, kind: .applicationSupport)
        XCTAssertNil(match)
    }

    func testDirectorySizeIncludesHiddenFiles() throws {
        let root = try TestFixtures.temporaryDirectory(named: "hidden-size")
        defer { try? FileManager.default.removeItem(at: root) }
        let hidden = root.appendingPathComponent(".hidden")
        try Data(repeating: 42, count: 1_048_576).write(to: hidden)
        let calculator = FileSizeCalculator()
        XCTAssertEqual(try calculator.sizeOfItem(at: root), try calculator.sizeOfItem(at: hidden))
    }

    func testUnreadableExistingFileIsNotVerifiedDeleted() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "denied-verification")
        let file = root.appendingPathComponent("existing")
        try Data([1]).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: root.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let candidate = RelatedFileCandidate(url: file, kind: .cache, size: 1, matchReason: "fixture", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let result = await DeletionVerifier().verify(candidate: candidate, wasSelected: true)
        XCTAssertEqual(result.status, .permissionDenied)
    }

    func testRelatedFileSizeFailureReportsIncompleteCoverage() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "size-failure")
        defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appendingPathComponent("Library/Caches/com.audit.sizing")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let app = makeApp(name: "Sizing", bundleID: "com.audit.sizing")
        let scanner = RelatedFileScanner(homeDirectory: home, sizeCalculator: FileSizeCalculator(sizeProvider: { _, _ in throw CocoaError(.fileReadNoPermission) }))
        let result = await scanner.scanRelatedFilesWithCoverage(for: app)
        XCTAssertTrue(result.issues.contains { $0.path == cache.path })
        XCTAssertFalse(result.value.contains { $0.url == cache && $0.defaultSelected })
    }

    func testInstalledCommandLineLaunchAgentIsNotAnOrphan() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "cli-owner")
        defer { try? FileManager.default.removeItem(at: home) }
        let agent = home.appendingPathComponent("Library/LaunchAgents/ai.audit.gateway.plist")
        try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["Label": "ai.audit.gateway", "ProgramArguments": ["/bin/sh", "-c", "true"]], format: .xml, options: 0)
        try data.write(to: agent)
        let result = await OrphanFileScanner(homeDirectory: home, installedApps: []).scanWithCoverage()
        XCTAssertFalse(result.value.flatMap(\.candidates).contains { $0.url == agent })
    }
}
