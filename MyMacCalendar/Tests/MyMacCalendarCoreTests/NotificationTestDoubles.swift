import Foundation
@testable import MyMacCalendarCore

@MainActor
final class FakeNotificationClient: NotificationClient {
    enum Operation: Equatable {
        case authorizationState
        case requestAuthorization
        case pendingIdentifiers
        case add(String)
        case remove([String])
    }

    var authorizationResult: NotificationAuthorizationState = .authorized
    var requestAuthorizationResult = true
    var authorizationError: (any Error)?
    var addFailureCalls: Set<Int> = []
    var blockedAuthorizationCalls: Set<Int> = []
    var blockedAddCalls: Set<Int> = []
    var pending: Set<String> = []
    private(set) var operations: [Operation] = []
    private(set) var authorizationCallCount = 0
    private(set) var addCallCount = 0

    private var authorizationContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var addContinuations: [Int: CheckedContinuation<Void, Never>] = [:]

    func authorizationState() async throws -> NotificationAuthorizationState {
        authorizationCallCount += 1
        let call = authorizationCallCount
        operations.append(.authorizationState)
        if blockedAuthorizationCalls.contains(call) {
            await withCheckedContinuation { continuation in
                authorizationContinuations[call] = continuation
            }
        }
        if let authorizationError { throw authorizationError }
        return authorizationResult
    }

    func requestAuthorization() async throws -> Bool {
        operations.append(.requestAuthorization)
        if let authorizationError { throw authorizationError }
        return requestAuthorizationResult
    }

    func pendingIdentifiers() async throws -> [String] {
        operations.append(.pendingIdentifiers)
        return pending.sorted()
    }

    func add(_ request: ScheduledNotificationRequest) async throws {
        addCallCount += 1
        let call = addCallCount
        operations.append(.add(request.identifier))
        if blockedAddCalls.contains(call) {
            await withCheckedContinuation { continuation in
                addContinuations[call] = continuation
            }
        }
        if addFailureCalls.contains(call) {
            throw FakeNotificationError.addFailed
        }
        pending.insert(request.identifier)
    }

    func removePending(identifiers: [String]) async {
        let sorted = identifiers.sorted()
        operations.append(.remove(sorted))
        pending.subtract(sorted)
    }

    func waitForAuthorizationCalls(_ count: Int) async {
        while authorizationCallCount < count { await Task.yield() }
    }

    func waitForAddCalls(_ count: Int) async {
        while addCallCount < count { await Task.yield() }
    }

    func resumeAuthorization(call: Int) {
        authorizationContinuations.removeValue(forKey: call)?.resume()
    }

    func resumeAdd(call: Int) {
        addContinuations.removeValue(forKey: call)?.resume()
    }
}

enum FakeNotificationError: Error {
    case authorizationFailed
    case addFailed
}

@MainActor
final class OneShotAsyncGate {
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var hasEntered = false
    private var hasPassed = false

    func wait() async {
        guard hasPassed == false else { return }
        hasEntered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        hasPassed = true
    }

    func waitUntilEntered() async {
        if hasEntered { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
