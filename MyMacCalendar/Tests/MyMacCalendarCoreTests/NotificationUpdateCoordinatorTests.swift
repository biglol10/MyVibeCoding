import XCTest
@testable import MyMacCalendarCore

@MainActor
final class NotificationUpdateCoordinatorTests: XCTestCase {
    func testDeleteWhileAuthorizationIsPendingPreventsOldAddAndRemovesExisting() async throws {
        let client = FakeNotificationClient()
        let old = identifier(eventID: firstEventID, batch: "old")
        client.pending = [old]
        client.blockedAuthorizationCalls = [1]
        let coordinator = NotificationUpdateCoordinator(client: client)
        let replacement = Task {
            try await coordinator.replace(
                eventID: firstEventID,
                requests: [request(eventID: firstEventID, batch: "new")]
            )
        }

        await client.waitForAuthorizationCalls(1)
        let deletion = Task { try await coordinator.delete(eventID: firstEventID) }
        client.resumeAuthorization(call: 1)

        _ = try? await replacement.value
        _ = try await deletion.value
        XCTAssertTrue(client.pending.isEmpty)
        XCTAssertEqual(client.addCallCount, 0)
    }

    func testRapidReplacementKeepsOnlyNewestBatchWhenOldAddFinishesLate() async throws {
        let client = FakeNotificationClient()
        client.blockedAddCalls = [1]
        let coordinator = NotificationUpdateCoordinator(client: client)
        let oldRequest = request(eventID: firstEventID, batch: "old")
        let newRequest = request(eventID: firstEventID, batch: "new")
        let oldTask = Task {
            try await coordinator.replace(eventID: firstEventID, requests: [oldRequest])
        }

        await client.waitForAddCalls(1)
        let newTask = Task {
            try await coordinator.replace(eventID: firstEventID, requests: [newRequest])
        }
        await client.waitForAddCalls(2)
        _ = try await newTask.value
        client.resumeAdd(call: 1)
        _ = try? await oldTask.value

        XCTAssertEqual(client.pending, [newRequest.identifier])
        XCTAssertTrue(client.operations.contains(.remove([oldRequest.identifier])))
    }

    func testDeleteWaitsForLateOldAddThenLeavesNoOrphan() async throws {
        let client = FakeNotificationClient()
        client.blockedAddCalls = [1]
        let coordinator = NotificationUpdateCoordinator(client: client)
        let late = request(eventID: firstEventID, batch: "late")
        let replacement = Task {
            try await coordinator.replace(eventID: firstEventID, requests: [late])
        }

        await client.waitForAddCalls(1)
        let deletion = Task { try await coordinator.delete(eventID: firstEventID) }
        client.resumeAdd(call: 1)

        _ = try? await replacement.value
        _ = try await deletion.value
        XCTAssertTrue(client.pending.isEmpty)
    }

    func testStartupCleanupRemovesOnlyUnknownEventNotifications() async throws {
        let client = FakeNotificationClient()
        let valid = identifier(eventID: firstEventID, batch: "valid")
        let orphan = identifier(eventID: secondEventID, batch: "orphan")
        client.pending = [valid, orphan, "unrelated-app-request"]
        let coordinator = NotificationUpdateCoordinator(client: client)

        try await coordinator.cleanupOrphans(validEventIDs: [firstEventID])

        XCTAssertEqual(client.pending, [valid, "unrelated-app-request"])
        XCTAssertTrue(client.operations.contains(.remove([orphan])))
    }

    func testStaleRefreshDoesNotEnqueueEventDeletedBetweenEventUpdates() async throws {
        let client = FakeNotificationClient()
        let gate = OneShotAsyncGate()
        let coordinator = NotificationUpdateCoordinator(
            client: client,
            betweenEvents: { await gate.wait() }
        )
        let now = try date(2026, 7, 1, hour: 8)
        let first = snapshot(id: firstEventID, title: "First", date: try date(2026, 7, 2))
        let second = snapshot(id: secondEventID, title: "Second", date: try date(2026, 7, 3))
        let refresh = Task {
            await coordinator.refresh(
                events: [first, second],
                defaultHour: 9,
                defaultMinute: 0,
                now: now,
                horizonDays: 90,
                maximumPlans: 64
            )
        }

        await gate.waitUntilEntered()
        try await coordinator.delete(eventID: secondEventID)
        gate.release()
        await refresh.value

        let secondPrefix = "event-\(secondEventID.uuidString.lowercased())-"
        XCTAssertFalse(client.operations.contains { operation in
            if case .add(let identifier) = operation {
                return identifier.hasPrefix(secondPrefix)
            }
            return false
        })
    }

    func testNewRefreshInvalidatesInFlightEventMissingFromLatestSnapshot() async throws {
        let client = FakeNotificationClient()
        client.blockedAddCalls = [1]
        let coordinator = NotificationUpdateCoordinator(client: client)
        let now = try date(2026, 7, 1, hour: 8)
        let stale = snapshot(id: firstEventID, title: "Stale", date: try date(2026, 7, 2))
        let oldRefresh = Task {
            await coordinator.refresh(
                events: [stale],
                defaultHour: 9,
                defaultMinute: 0,
                now: now,
                maximumPlans: 64
            )
        }

        await client.waitForAddCalls(1)
        await coordinator.refresh(
            events: [],
            defaultHour: 9,
            defaultMinute: 0,
            now: now,
            maximumPlans: 64
        )
        client.resumeAdd(call: 1)
        await oldRefresh.value

        XCTAssertTrue(client.pending.isEmpty)
    }

    private let firstEventID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private let secondEventID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func request(eventID: UUID, batch: String) -> ScheduledNotificationRequest {
        ScheduledNotificationRequest(
            identifier: identifier(eventID: eventID, batch: batch),
            eventID: eventID,
            title: "Private title",
            body: "Private body",
            fireDate: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }

    private func identifier(eventID: UUID, batch: String) -> String {
        "event-\(eventID.uuidString.lowercased())-occurrence-20260701-offset-0-batch-\(batch)"
    }

    private func snapshot(id: UUID, title: String, date: Date) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            title: title,
            startDate: date,
            endDate: date,
            colorHex: "#4F7DFF",
            recurrence: .none,
            notificationOffsetsDays: [0]
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }
}
