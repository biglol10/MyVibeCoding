import XCTest
@testable import MyMacCleanCore

final class DeveloperCacheScannerTests: XCTestCase {
    func testScannerFindsExistingKnownTargetsWithSafetyAndSize() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "developer-cache-scan")
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        let archives = home.appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)
        let swiftPM = home.appendingPathComponent("Library/Caches/org.swift.swiftpm", isDirectory: true)
        let npm = home.appendingPathComponent(".npm", isDirectory: true)
        let yarn = home.appendingPathComponent("Library/Caches/Yarn", isDirectory: true)
        let pnpm = home.appendingPathComponent("Library/pnpm/store", isDirectory: true)
        let cocoaPods = home.appendingPathComponent("Library/Caches/CocoaPods", isDirectory: true)
        let gradle = home.appendingPathComponent(".gradle/caches", isDirectory: true)

        try writePayload(in: derivedData, name: "build.noindex/data.bin", size: 12)
        try writePayload(in: archives, name: "App.xcarchive/info.plist", size: 13)
        try writePayload(in: swiftPM, name: "repositories/checkouts.bin", size: 14)
        try writePayload(in: npm, name: "_cacache/content.bin", size: 15)
        try writePayload(in: yarn, name: "v6/package.tgz", size: 16)
        try writePayload(in: pnpm, name: "v3/files/index.bin", size: 17)
        try writePayload(in: cocoaPods, name: "Pods/Specs.zip", size: 18)
        try writePayload(in: gradle, name: "modules-2/files.bin", size: 19)

        let results = try await DeveloperCacheScanner(homeDirectory: home).scan()

        XCTAssertEqual(results.map(\.tool), [
            .xcodeDerivedData,
            .xcodeArchives,
            .swiftPackageManager,
            .npm,
            .yarn,
            .pnpm,
            .cocoaPods,
            .gradle
        ])
        XCTAssertEqual(results.first(where: { $0.tool == .xcodeDerivedData })?.safety, .safe)
        XCTAssertEqual(results.first(where: { $0.tool == .swiftPackageManager })?.safety, .safe)
        XCTAssertEqual(results.first(where: { $0.tool == .npm })?.safety, .safe)
        XCTAssertEqual(results.first(where: { $0.tool == .yarn })?.safety, .safe)
        XCTAssertEqual(results.first(where: { $0.tool == .pnpm })?.safety, .safe)
        XCTAssertEqual(results.first(where: { $0.tool == .xcodeArchives })?.safety, .review)
        XCTAssertEqual(results.first(where: { $0.tool == .cocoaPods })?.safety, .review)
        XCTAssertEqual(results.first(where: { $0.tool == .gradle })?.safety, .review)
        XCTAssertGreaterThan(results.first(where: { $0.tool == .xcodeDerivedData })?.size ?? 0, 0)
        XCTAssertTrue(results.first(where: { $0.tool == .xcodeDerivedData })?.explanation.contains("Close Xcode") ?? false)
        XCTAssertTrue(results.allSatisfy { !$0.explanation.isEmpty })
    }

    func testScannerSkipsMissingTargets() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "developer-cache-missing")
        let swiftPM = home.appendingPathComponent("Library/Caches/org.swift.swiftpm", isDirectory: true)
        try writePayload(in: swiftPM, name: "cache.bin", size: 20)

        let results = try await DeveloperCacheScanner(homeDirectory: home).scan()

        XCTAssertEqual(results.map(\.tool), [.swiftPackageManager])
        XCTAssertEqual(results.map(\.url), [swiftPM])
    }

    func testScannerReportsDockerTargetAsReadOnly() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "developer-cache-docker")
        let dockerStorage = home.appendingPathComponent("Library/Containers/com.docker.docker/Data", isDirectory: true)
        try writePayload(in: dockerStorage, name: "vms/0/disk.raw", size: 21)

        let results = try await DeveloperCacheScanner(
            homeDirectory: home,
            dockerStorageURL: dockerStorage
        ).scan()

        XCTAssertEqual(results.map(\.tool), [.docker])
        XCTAssertEqual(results.first?.safety, .readOnly)
        XCTAssertFalse(results.first?.isDeletable ?? true)
        XCTAssertFalse(results.first?.defaultSelected ?? true)
    }

    private func writePayload(in directory: URL, name: String, size: Int) throws {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: size).write(to: url)
    }
}
