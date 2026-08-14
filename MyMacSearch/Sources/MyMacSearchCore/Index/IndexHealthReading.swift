public protocol IndexHealthReading: Sendable {
    func snapshot(liveStates: [String: ScopeRuntimeState]) async throws -> IndexHealthSnapshot
    func issues(scopeID: String?, unresolvedOnly: Bool, limit: Int) async throws -> [IndexIssueRecord]
}

public protocol IndexVerifying: Sendable {
    func verify() async throws -> IndexVerificationResult
}
