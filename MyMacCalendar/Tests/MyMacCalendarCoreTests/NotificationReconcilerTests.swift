import XCTest
@testable import MyMacCalendarCore

@MainActor
final class NotificationReconcilerTests: XCTestCase {
    func testDeniedAuthorizationDoesNotReadOrMutatePendingRequests() async throws {
        let client = FakeNotificationClient()
        client.authorizationResult = .denied
        let reconciler = NotificationReconciler(client: client)

        let outcome = try await reconciler.reconcile(
            eventID: eventID,
            desired: [request("new-1")],
            isCurrent: { true }
        )

        XCTAssertEqual(outcome, .notAuthorized)
        XCTAssertEqual(client.operations, [.authorizationState])
    }

    func testAuthorizationLookupErrorDoesNotMutatePendingRequests() async {
        let client = FakeNotificationClient()
        client.authorizationError = FakeNotificationError.authorizationFailed
        let reconciler = NotificationReconciler(client: client)

        do {
            _ = try await reconciler.reconcile(
                eventID: eventID,
                desired: [request("new-1")],
                isCurrent: { true }
            )
            XCTFail("Expected authorization failure")
        } catch {
            XCTAssertTrue(error is FakeNotificationError)
        }
        XCTAssertEqual(client.operations, [.authorizationState])
    }

    func testRequestedAuthorizationDenialDoesNotMutatePendingRequests() async throws {
        let client = FakeNotificationClient()
        client.authorizationResult = .notDetermined
        client.requestAuthorizationResult = false
        let reconciler = NotificationReconciler(client: client)

        let outcome = try await reconciler.reconcile(
            eventID: eventID,
            desired: [request("new-1")],
            isCurrent: { true }
        )

        XCTAssertEqual(outcome, .notAuthorized)
        XCTAssertEqual(client.operations, [.authorizationState, .requestAuthorization])
    }

    func testStartupCleanupDoesNotPromptWhenAuthorizationIsUndetermined() async throws {
        let client = FakeNotificationClient()
        client.authorizationResult = .notDetermined
        let reconciler = NotificationReconciler(client: client)

        let outcome = try await reconciler.cleanupOrphans(
            validEventIDs: [],
            isCurrent: { true }
        )

        XCTAssertEqual(outcome, .notAuthorized)
        XCTAssertEqual(client.operations, [.authorizationState])
    }

    func testDeleteDoesNotPromptWhenAuthorizationIsUndetermined() async throws {
        let client = FakeNotificationClient()
        client.authorizationResult = .notDetermined
        let reconciler = NotificationReconciler(client: client)

        let outcome = try await reconciler.removeAll(
            eventID: eventID,
            isCurrent: { true }
        )

        XCTAssertEqual(outcome, .notAuthorized)
        XCTAssertEqual(client.operations, [.authorizationState])
    }

    func testEmptyReplacementDoesNotPromptWhenAuthorizationIsUndetermined() async throws {
        let client = FakeNotificationClient()
        client.authorizationResult = .notDetermined
        let reconciler = NotificationReconciler(client: client)

        let outcome = try await reconciler.reconcile(
            eventID: eventID,
            desired: [],
            isCurrent: { true }
        )

        XCTAssertEqual(outcome, .notAuthorized)
        XCTAssertEqual(client.operations, [.authorizationState])
    }

    func testSecondAddFailureRemovesEntireStagedBatchAndKeepsOldBatch() async {
        let client = FakeNotificationClient()
        let old = identifier("old")
        client.pending = [old]
        client.addFailureCalls = [2]
        let first = request("new-1")
        let second = request("new-2")
        let reconciler = NotificationReconciler(client: client)

        do {
            _ = try await reconciler.reconcile(
                eventID: eventID,
                desired: [first, second],
                isCurrent: { true }
            )
            XCTFail("Expected second add failure")
        } catch {
            XCTAssertTrue(error is FakeNotificationError)
        }

        XCTAssertEqual(client.pending, [old])
        XCTAssertEqual(client.operations, [
            .authorizationState,
            .pendingIdentifiers,
            .add(first.identifier),
            .add(second.identifier),
            .remove([first.identifier, second.identifier])
        ])
    }

    func testAddsEntireNewBatchBeforeRemovingStaleIdentifiers() async throws {
        let client = FakeNotificationClient()
        let old = identifier("old")
        client.pending = [old]
        let first = request("new-1")
        let second = request("new-2")
        let reconciler = NotificationReconciler(client: client)

        let outcome = try await reconciler.reconcile(
            eventID: eventID,
            desired: [first, second],
            isCurrent: { true }
        )

        XCTAssertEqual(outcome, .updated)
        XCTAssertEqual(client.pending, [first.identifier, second.identifier])
        XCTAssertEqual(client.operations, [
            .authorizationState,
            .pendingIdentifiers,
            .add(first.identifier),
            .add(second.identifier),
            .remove([old])
        ])
    }

    func testCancellationWhileAddIsInFlightCleansLateAddition() async {
        let client = FakeNotificationClient()
        client.blockedAddCalls = [1]
        let staged = request("staged")
        let reconciler = NotificationReconciler(client: client)
        let task = Task {
            try await reconciler.reconcile(
                eventID: eventID,
                desired: [staged],
                isCurrent: { true }
            )
        }

        await client.waitForAddCalls(1)
        task.cancel()
        client.resumeAdd(call: 1)

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(client.pending.isEmpty)
        XCTAssertTrue(client.operations.contains(.remove([staged.identifier])))
    }

    private let eventID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

    private func request(_ suffix: String) -> ScheduledNotificationRequest {
        ScheduledNotificationRequest(
            identifier: identifier(suffix),
            eventID: eventID,
            title: "Private title",
            body: "Private body",
            fireDate: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }

    private func identifier(_ suffix: String) -> String {
        "event-\(eventID.uuidString.lowercased())-occurrence-20260701-offset-0-batch-\(suffix)"
    }
}
