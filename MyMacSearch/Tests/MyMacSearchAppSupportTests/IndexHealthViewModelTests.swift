import Foundation
import XCTest
@testable import MyMacSearchAppSupport
@testable import MyMacSearchCore

final class IndexHealthViewModelTests: XCTestCase {
    @MainActor
    func testSlowOldRefreshCannotReplaceNewSnapshot() async throws {
        let reader = DelayedHealthReader()
        let model = IndexHealthViewModel(reader: reader, verifier: HealthyVerifier())

        model.refresh(liveStates: ["old": ScopeRuntimeState(state: .watching)])
        model.refresh(liveStates: ["new": ScopeRuntimeState(state: .watching)])

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
