import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class AuditRegressionTests: XCTestCase {
    func testSwitchingAppsDiscardsInFlightScan() async throws {
        let gate = AuditScanGate<[RelatedFileCandidate]>()
        let alpha = makeApp("Alpha")
        let beta = makeApp("Beta")
        let model = ApplicationListViewModel(relatedFileScanning: RelatedFileScanning { _ in await gate.wait() })
        model.apps = [alpha, beta]
        model.selectApp(alpha)
        let task = Task { await model.scanSelectedApp() }
        while !(await gate.started) { await Task.yield() }
        model.selectApp(beta)
        await gate.finish([makeCandidate(alpha.bundleURL)])
        await task.value
        XCTAssertEqual(model.selectedApp, beta)
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertThrowsError(try model.makePlan())
    }

    func testRescanPreservesResetModeAndExcludesBundle() async {
        let app = makeApp("Reset")
        let bundle = makeCandidate(app.bundleURL)
        let model = ApplicationListViewModel(relatedFileScanning: RelatedFileScanning { _ in ScanResult(value: [bundle], issues: []) })
        model.apps = [app]
        model.selectApp(app)
        await model.scanSelectedApp()
        model.cleanupMode = .resetData
        await model.scanSelectedApp()
        XCTAssertEqual(model.cleanupMode, .resetData)
        XCTAssertTrue(model.selectedReviewCandidates.isEmpty)
        XCTAssertFalse(model.selectedCandidateIDs.contains(bundle.id))
    }

    func testInstalledAppsChangeInvalidatesInFlightOrphanScan() async {
        let gate = AuditScanGate<[OrphanFileGroup]>()
        let model = OrphanFilesViewModel(installedApps: [], orphanFileScanning: OrphanFileScanning { _ in await gate.wait() })
        let task = Task { await model.loadGroups() }
        while !(await gate.started) { await Task.yield() }
        model.updateInstalledApps([makeApp("Alpha")])
        await gate.finish([OrphanFileGroup(inferredName: "Alpha", inferredIdentifier: "com.audit.Alpha", candidates: [makeCandidate(URL(fileURLWithPath: "/tmp/alpha"))])])
        await task.value
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertFalse(model.hasScanned)
    }

    private func makeApp(_ name: String) -> InstalledApp {
        InstalledApp(displayName: name, bundleIdentifier: "com.audit.\(name)", version: nil, executableName: name, bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"), iconIdentifier: nil, bundleSize: 100, lastOpenedAt: nil)
    }

    private func makeCandidate(_ url: URL) -> RelatedFileCandidate {
        RelatedFileCandidate(url: url, kind: .appBundle, size: 100, matchReason: "fixture", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
    }
}

private actor AuditScanGate<Value: Sendable> {
    var started = false
    private var continuation: CheckedContinuation<ScanResult<Value>, Never>?
    func wait() async -> ScanResult<Value> {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ value: Value) { continuation?.resume(returning: ScanResult(value: value, issues: [])) }
}
