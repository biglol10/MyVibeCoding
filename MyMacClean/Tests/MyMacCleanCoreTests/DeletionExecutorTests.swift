import XCTest
@testable import MyMacCleanCore

final class DeletionExecutorTests: XCTestCase {
    func testExecutorMovesPlannedFilesToTrashByDefault() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "executor")
        let appURL = root.appendingPathComponent("Figma.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.figma.Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: nil, executableName: "Figma", bundleURL: appURL, iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: cacheURL, kind: .cache, size: 0, matchReason: "test", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [candidate], createdAt: Date(timeIntervalSince1970: 0))
        let recorder = RemovalRecorder()

        let results = await DeletionExecutor(
            fileRemover: recorder.fileRemover,
            protectionPolicy: ProtectionPolicy(homeDirectory: root)
        ).execute(plan: plan, confirmation: "DELETE")

        XCTAssertEqual(results, [DeletionItemResult(path: cacheURL.path, success: true, errorMessage: nil)])
        XCTAssertEqual(recorder.trashedURLs, [cacheURL])
        XCTAssertEqual(recorder.removedURLs, [])
    }

    func testExecutorPermanentlyRemovesPlannedFilesOnlyWhenPermanentModeIsRequested() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "executor-permanent")
        let appURL = root.appendingPathComponent("Figma.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.figma.Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: nil, executableName: "Figma", bundleURL: appURL, iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: cacheURL, kind: .cache, size: 0, matchReason: "test", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [candidate], createdAt: Date(timeIntervalSince1970: 0))
        let recorder = RemovalRecorder()

        let results = await DeletionExecutor(
            fileRemover: recorder.fileRemover,
            protectionPolicy: ProtectionPolicy(homeDirectory: root)
        ).execute(plan: plan, confirmation: "DELETE", mode: .permanent)

        XCTAssertEqual(results, [DeletionItemResult(path: cacheURL.path, success: true, errorMessage: nil)])
        XCTAssertEqual(recorder.trashedURLs, [])
        XCTAssertEqual(recorder.removedURLs, [cacheURL])
    }

    func testExecutorForceDeletesImmutableFiles() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "executor-force")
        let appURL = root.appendingPathComponent("Figma.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.figma.Desktop", isDirectory: true)
        let lockedFileURL = cacheURL.appendingPathComponent("locked-cache")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8).write(to: lockedFileURL)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: lockedFileURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: lockedFileURL.path) }

        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: nil, executableName: "Figma", bundleURL: appURL, iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: cacheURL, kind: .cache, size: 0, matchReason: "test", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [candidate], createdAt: Date(timeIntervalSince1970: 0))

        let results = await DeletionExecutor(
            protectionPolicy: ProtectionPolicy(homeDirectory: root)
        ).execute(plan: plan, confirmation: "DELETE", force: true, mode: .permanent)

        XCTAssertEqual(results, [DeletionItemResult(path: cacheURL.path, success: true, errorMessage: nil)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testForcePreparationDoesNotMutateSymlinkTargets() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "executor-force-symlink")
        let appURL = root.appendingPathComponent("Figma.app", isDirectory: true)
        let cacheRoot = root.appendingPathComponent("Library/Caches", isDirectory: true)
        let targetDirectory = root.appendingPathComponent("Library/Application Support/ExternalTarget", isDirectory: true)
        let targetFile = targetDirectory.appendingPathComponent("cache.db")
        let symlinkURL = cacheRoot.appendingPathComponent("com.figma.Symlink", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: targetFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: targetDirectory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: targetFile.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: targetDirectory.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetFile.path)
        }
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetDirectory)

        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: nil, executableName: "Figma", bundleURL: appURL, iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: symlinkURL, kind: .cache, size: 0, matchReason: "test", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [candidate], createdAt: Date(timeIntervalSince1970: 0))
        let recorder = RemovalRecorder()

        _ = await DeletionExecutor(
            fileRemover: recorder.fileRemover,
            protectionPolicy: ProtectionPolicy(homeDirectory: root)
        ).execute(plan: plan, confirmation: "DELETE", force: true, mode: .permanent)

        XCTAssertEqual(try posixPermissions(of: targetDirectory), 0o500)
        XCTAssertEqual(try posixPermissions(of: targetFile), 0o400)
        XCTAssertEqual(recorder.removedURLs, [symlinkURL])
    }

    func testExecutorRejectsProtectedCandidatesAtExecutionTime() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "executor-protected")
        let appURL = root.appendingPathComponent("Figma.app", isDirectory: true)
        let protectedURL = root.appendingPathComponent("Documents/Figma Export", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: protectedURL, withIntermediateDirectories: true)

        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: nil, executableName: "Figma", bundleURL: appURL, iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: protectedURL, kind: .unknown, size: 0, matchReason: "test", confidence: .low, defaultSelected: true, requiresManualReview: true, isProtected: true)
        let plan = DeletionPlan(app: app, candidates: [candidate], createdAt: Date(timeIntervalSince1970: 0))

        let results = await DeletionExecutor(
            protectionPolicy: ProtectionPolicy(homeDirectory: root)
        ).execute(plan: plan, confirmation: "DELETE")

        XCTAssertEqual(results, [DeletionItemResult(path: protectedURL.path, success: false, errorMessage: "protected path skipped")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedURL.path))
    }

    func testExecutorRechecksProtectionPolicyAtExecutionTime() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "executor-policy-recheck")
        let appURL = home.appendingPathComponent("Applications/Figma.app", isDirectory: true)
        let protectedURL = home.appendingPathComponent("Documents/Figma Export", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: protectedURL, withIntermediateDirectories: true)

        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: nil, executableName: "Figma", bundleURL: appURL, iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let staleCandidate = RelatedFileCandidate(url: protectedURL, kind: .cache, size: 0, matchReason: "stale", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [staleCandidate], createdAt: Date(timeIntervalSince1970: 0))
        let recorder = RemovalRecorder()

        let results = await DeletionExecutor(
            fileRemover: recorder.fileRemover,
            protectionPolicy: ProtectionPolicy(homeDirectory: home)
        ).execute(plan: plan, confirmation: "DELETE")

        XCTAssertEqual(results, [DeletionItemResult(path: protectedURL.path, success: false, errorMessage: "protected path skipped")])
        XCTAssertEqual(recorder.trashedURLs, [])
        XCTAssertEqual(recorder.removedURLs, [])
    }

    func testExecutorReportsPathMissingBeforeDelete() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "executor-missing")
        let appURL = root.appendingPathComponent("Figma.app", isDirectory: true)
        let missingURL = root.appendingPathComponent("Library/Caches/com.figma.Missing", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: nil, executableName: "Figma", bundleURL: appURL, iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: missingURL, kind: .cache, size: 0, matchReason: "test", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [candidate], createdAt: Date(timeIntervalSince1970: 0))

        let results = await DeletionExecutor(
            protectionPolicy: ProtectionPolicy(homeDirectory: root)
        ).execute(plan: plan, confirmation: "DELETE")

        XCTAssertEqual(results, [DeletionItemResult(path: missingURL.path, success: false, errorMessage: "path not found before delete")])
    }

    func testExecutorRejectsMissingConfirmationPhrase() async throws {
        let app = InstalledApp(displayName: "Figma", bundleIdentifier: nil, version: nil, executableName: nil, bundleURL: URL(fileURLWithPath: "/tmp/Figma.app"), iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: URL(fileURLWithPath: "/tmp/Figma-cache"), kind: .cache, size: 0, matchReason: "test", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [candidate])

        let results = await DeletionExecutor().execute(plan: plan, confirmation: "delete figma")

        XCTAssertEqual(results, [DeletionItemResult(path: "/tmp/Figma-cache", success: false, errorMessage: "confirmation phrase mismatch")])
    }

    func testExecutorRejectsAppNameInConfirmationPhrase() async throws {
        let app = InstalledApp(displayName: "Figma", bundleIdentifier: nil, version: nil, executableName: nil, bundleURL: URL(fileURLWithPath: "/tmp/Figma.app"), iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: URL(fileURLWithPath: "/tmp/Figma-cache"), kind: .cache, size: 0, matchReason: "test", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [candidate])

        let results = await DeletionExecutor().execute(plan: plan, confirmation: "DELETE Figma")

        XCTAssertEqual(results, [DeletionItemResult(path: "/tmp/Figma-cache", success: false, errorMessage: "confirmation phrase mismatch")])
    }
}

private final class RemovalRecorder: @unchecked Sendable {
    private(set) var trashedURLs: [URL] = []
    private(set) var removedURLs: [URL] = []

    var fileRemover: DeletionFileRemover {
        DeletionFileRemover(
            trash: { [self] url in trashedURLs.append(url) },
            remove: { [self] url in removedURLs.append(url) }
        )
    }
}

private func posixPermissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
}
