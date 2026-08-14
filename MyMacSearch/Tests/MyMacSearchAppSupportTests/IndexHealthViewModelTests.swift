import Foundation
import XCTest
@testable import MyMacSearchAppSupport
@testable import MyMacSearchCore

final class IndexHealthViewModelTests: XCTestCase {
    @MainActor
    func testSlowOldRefreshCannotReplaceNewSnapshot() async throws {
        let reader = DelayedHealthReader()
        let model = IndexHealthViewModel(reader: reader, verifier: HealthyVerifier())

        model.refresh(liveStates: ["old": ScopeRuntimeState(state: .watching)], force: true)
        model.refresh(liveStates: ["new": ScopeRuntimeState(state: .watching)], force: true)

        try await eventually { model.snapshot?.totalEntryCount == 2 }
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(model.snapshot?.totalEntryCount, 2)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testVerifyPublishesStructuredResult() async throws {
        let model = IndexHealthViewModel(reader: DelayedHealthReader(), verifier: HealthyVerifier())

        model.verify()

        try await eventually { model.verification?.isHealthy == true }
        XCTAssertFalse(model.isVerifying)
    }

    @MainActor
    func testRapidProgressRefreshesReuseDatabaseSnapshotAndMergeLiveState() async throws {
        let reader = CountingHealthReader()
        let model = IndexHealthViewModel(reader: reader, verifier: HealthyVerifier())
        model.refresh(liveStates: ["home": ScopeRuntimeState(state: .scanning)])
        try await eventually { model.snapshot != nil }

        for count in 1...20 {
            model.refresh(liveStates: [
                "home": ScopeRuntimeState(
                    state: .scanning,
                    progress: IndexProgress(scannedCount: count)
                )
            ])
        }

        let snapshotCount = await reader.snapshotCount()
        XCTAssertEqual(snapshotCount, 1)
        XCTAssertEqual(model.snapshot?.scopes.first?.progress.scannedCount, 20)
    }

    @MainActor
    func testCachedCompletionSchedulesTrailingDatabaseRefresh() async throws {
        let reader = CountingHealthReader()
        let model = IndexHealthViewModel(reader: reader, verifier: HealthyVerifier())
        model.refresh(liveStates: ["home": ScopeRuntimeState(state: .scanning)])
        try await eventually { model.snapshot != nil }

        model.refresh(liveStates: ["home": ScopeRuntimeState(state: .watching)])

        try await eventually(timeout: .seconds(2)) { await reader.snapshotCount() == 2 }
        XCTAssertEqual(model.snapshot?.scopes.first?.state, .watching)
    }
}

private actor CountingHealthReader: IndexHealthReading {
    private var calls = 0

    func snapshot(liveStates: [String: ScopeRuntimeState]) async throws -> IndexHealthSnapshot {
        calls += 1
        return IndexHealthSnapshot(
            scopes: [
                IndexScopeHealth(
                    scopeID: "home",
                    rootPath: "/Users/test",
                    volumeType: .internalLocal,
                    isEnabled: true,
                    state: .paused,
                    entryCount: 1,
                    lastCompletedScanAt: nil,
                    lastEventAt: nil,
                    lastEventID: nil,
                    unresolvedIssueCount: 0,
                    lastError: nil
                )
            ],
            totalEntryCount: 1,
            databaseBytes: 1,
            auxiliaryBytes: 0
        )
    }

    func issues(scopeID: String?, unresolvedOnly: Bool, limit: Int) async throws -> [IndexIssueRecord] {
        []
    }

    func snapshotCount() -> Int { calls }
}

private actor DelayedHealthReader: IndexHealthReading {
    func snapshot(liveStates: [String: ScopeRuntimeState]) async throws -> IndexHealthSnapshot {
        if liveStates["old"] != nil {
            try await Task.sleep(for: .milliseconds(150))
            return IndexHealthSnapshot(scopes: [], totalEntryCount: 1, databaseBytes: 1, auxiliaryBytes: 0)
        }
        try await Task.sleep(for: .milliseconds(10))
        return IndexHealthSnapshot(scopes: [], totalEntryCount: 2, databaseBytes: 1, auxiliaryBytes: 0)
    }

    func issues(scopeID: String?, unresolvedOnly: Bool, limit: Int) async throws -> [IndexIssueRecord] {
        []
    }
}

private actor HealthyVerifier: IndexVerifying {
    func verify() async throws -> IndexVerificationResult {
        IndexVerificationResult(
            startedAt: Date(),
            completedAt: Date(),
            checks: [IndexVerificationCheck(name: "SQLite", passed: true, detail: "ok")]
        )
    }
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Condition was not met before timeout")
}
