import Foundation
import MyMacSearchCore
import Observation

@MainActor
@Observable
public final class IndexHealthViewModel {
    public private(set) var snapshot: IndexHealthSnapshot?
    public private(set) var issues: [IndexIssueRecord] = []
    public private(set) var verification: IndexVerificationResult?
    public private(set) var isRefreshing = false
    public private(set) var isVerifying = false
    public private(set) var errorMessage: String?

    private let reader: any IndexHealthReading
    private let verifier: any IndexVerifying
    private var refreshGeneration: UInt64 = 0
    private var verificationGeneration: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var verificationTask: Task<Void, Never>?
    private var lastLiveStates: [String: ScopeRuntimeState] = [:]

    public init(reader: any IndexHealthReading, verifier: any IndexVerifying) {
        self.reader = reader
        self.verifier = verifier
    }

    deinit {
        MainActor.assumeIsolated {
            refreshTask?.cancel()
            verificationTask?.cancel()
        }
    }

    public func refresh(liveStates: [String: ScopeRuntimeState], force: Bool = false) {
        if !force,
           liveStates == lastLiveStates,
           let snapshot,
           Date().timeIntervalSince(snapshot.capturedAt) < 1 {
            return
        }
        lastLiveStates = liveStates
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        isRefreshing = true
        refreshTask = Task { [weak self, reader] in
            do {
                async let loadedSnapshot = reader.snapshot(liveStates: liveStates)
                async let loadedIssues = reader.issues(scopeID: nil, unresolvedOnly: true, limit: 200)
                let values = try await (loadedSnapshot, loadedIssues)
                guard let self, self.refreshGeneration == generation, !Task.isCancelled else { return }
                self.snapshot = values.0
                self.issues = values.1
                self.errorMessage = nil
                self.isRefreshing = false
                self.refreshTask = nil
            } catch is CancellationError {
                guard let self, self.refreshGeneration == generation else { return }
                self.isRefreshing = false
                self.refreshTask = nil
            } catch {
                guard let self, self.refreshGeneration == generation else { return }
                self.errorMessage = error.localizedDescription
                self.isRefreshing = false
                self.refreshTask = nil
            }
        }
    }

    public func verify() {
        verificationGeneration &+= 1
        let generation = verificationGeneration
        verificationTask?.cancel()
        isVerifying = true
        verificationTask = Task { [weak self, verifier] in
            do {
                let result = try await verifier.verify()
                guard let self, self.verificationGeneration == generation, !Task.isCancelled else { return }
                self.verification = result
                self.errorMessage = nil
                self.isVerifying = false
                self.verificationTask = nil
            } catch is CancellationError {
                guard let self, self.verificationGeneration == generation else { return }
                self.isVerifying = false
                self.verificationTask = nil
            } catch {
                guard let self, self.verificationGeneration == generation else { return }
                self.errorMessage = error.localizedDescription
                self.isVerifying = false
                self.verificationTask = nil
            }
        }
    }
}
