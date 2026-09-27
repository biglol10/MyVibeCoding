import Foundation
import Combine

@MainActor
public final class NotificationUpdateCoordinator: ObservableObject {
    @Published public private(set) var status: NotificationRefreshStatus = .idle
    private let client: NotificationClient
    private struct EventOperation {
        let generation: UInt64
        let task: Task<NotificationReconcileOutcome, Error>
    }

    private let reconciler: NotificationReconciler
    private let planner: NotificationPlanner
    private let betweenEvents: @MainActor () async -> Void
    private var generations: [UUID: UInt64] = [:]
    private var operations: [UUID: EventOperation] = [:]
    private var deletedEventIDs = Set<UUID>()
    private var refreshGeneration: UInt64 = 0
    private var groupedOwnersByMember: [UUID: Set<UUID>] = [:]

    public init(
        client: NotificationClient,
        planner: NotificationPlanner = NotificationPlanner(),
        betweenEvents: @escaping @MainActor () async -> Void = {}
    ) {
        self.client = client
        self.reconciler = NotificationReconciler(client: client)
        self.planner = planner
        self.betweenEvents = betweenEvents
    }

    @discardableResult
    public func replace(
        eventID: UUID,
        requests: [ScheduledNotificationRequest]
    ) async throws -> NotificationReconcileOutcome {
        deletedEventIDs.remove(eventID)
        let generation = nextGeneration(for: eventID)
        operations[eventID]?.task.cancel()

        let task = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.reconciler.reconcile(
                eventID: eventID,
                desired: requests,
                isCurrent: { [weak self] in
                    self?.generations[eventID] == generation
                }
            )
        }
        operations[eventID] = EventOperation(generation: generation, task: task)

        do {
            let outcome = try await awaitOperation(task)
            clearOperation(eventID: eventID, generation: generation)
            return outcome
        } catch {
            clearOperation(eventID: eventID, generation: generation)
            throw error
        }
    }

    @discardableResult
    public func delete(eventID: UUID) async throws -> NotificationReconcileOutcome {
        refreshGeneration &+= 1
        deletedEventIDs.insert(eventID)
        // A reminder can share a request with other events. Cancel its owners
        // too so an in-flight aggregate cannot reintroduce the deleted title.
        let owners = (groupedOwnersByMember[eventID] ?? []).union([eventID])
        for owner in owners where owner != eventID {
            let ownerGeneration = nextGeneration(for: owner)
            let operation = operations.removeValue(forKey: owner)?.task
            operation?.cancel()
            if let operation { _ = await operation.result }
            _ = try await reconciler.removeAll(eventID: owner, isCurrent: { [weak self] in
                self?.generations[owner] == ownerGeneration
            })
        }
        let previous = operations[eventID]?.task
        let generation = nextGeneration(for: eventID)
        operations.removeValue(forKey: eventID)
        previous?.cancel()
        if let previous {
            _ = await previous.result
        }

        return try await reconciler.removeAll(
            eventID: eventID,
            isCurrent: { [weak self] in
                self?.generations[eventID] == generation && self?.deletedEventIDs.contains(eventID) == true
            }
        )
    }

    @discardableResult
    public func cleanupOrphans(validEventIDs: Set<UUID>) async throws -> NotificationReconcileOutcome {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let validIDs = validEventIDs.subtracting(deletedEventIDs)
        return try await reconciler.cleanupOrphans(
            validEventIDs: validIDs,
            isCurrent: { [weak self] in self?.refreshGeneration == generation }
        )
    }

    public func refresh(
        events: [CalendarEventSnapshot],
        defaultHour: Int,
        defaultMinute: Int,
        now: Date = Date(),
        horizonDays: Int = 90,
        maximumPlans: Int = 32
    ) async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        invalidateActiveOperations()
        let eventIDs = Set(events.map(\.id)).subtracting(deletedEventIDs)
        let batchID = UUID().uuidString.lowercased()

        do {
            _ = try await reconciler.cleanupOrphans(
                validEventIDs: eventIDs,
                isCurrent: { [weak self] in self?.refreshGeneration == generation }
            )
        } catch {
            if refreshGeneration == generation && !Task.isCancelled { status = .failed }
            logRefreshError(eventID: nil, error: error)
            return
        }

        let plans = planner.plans(
            for: events.filter { eventIDs.contains($0.id) },
            defaultHour: defaultHour,
            defaultMinute: defaultMinute,
            now: now,
            horizonDays: horizonDays,
            maximumPlans: Int.max,
            batchID: batchID
        )
        let schedule = NotificationSchedule(plans: plans, maximumRequests: maximumPlans, batchID: batchID)
        var newOwnersByMember: [UUID: Set<UUID>] = [:]
        for request in schedule.requests {
            for member in schedule.eventIDsByRequest[request.identifier] ?? [] {
                groupedOwnersByMember[member, default: []].insert(request.eventID)
                newOwnersByMember[member, default: []].insert(request.eventID)
            }
        }
        let requestsByEvent = Dictionary(grouping: schedule.requests, by: \.eventID)
        var failed = false
        var denied = false

        for event in events {
            guard refreshGeneration == generation,
                  deletedEventIDs.contains(event.id) == false else {
                continue
            }
            let requests = (requestsByEvent[event.id] ?? []).filter {
                schedule.eventIDsByRequest[$0.identifier, default: []].isDisjoint(with: deletedEventIDs)
            }
            do {
                let outcome = try await replace(eventID: event.id, requests: requests)
                denied = denied || outcome == .notAuthorized
            } catch is CancellationError {
                if refreshGeneration != generation || Task.isCancelled { return }
            } catch {
                failed = true
                logRefreshError(eventID: event.id, error: error)
            }

            await betweenEvents()
            if refreshGeneration != generation || Task.isCancelled { return }
        }
        guard refreshGeneration == generation, !Task.isCancelled else { return }
        do {
            let authorization = try await client.authorizationState()
            guard refreshGeneration == generation, !Task.isCancelled else { return }
            if authorization == .denied {
                status = .denied
            } else if authorization == .notDetermined {
                status = .permissionRequired
            } else if failed {
                status = .failed
            } else if denied {
                status = .denied
            } else {
                groupedOwnersByMember = newOwnersByMember
                status = .scheduled(reminders: schedule.scheduledReminderCount,
                                    requests: schedule.requests.count,
                                    deferred: schedule.deferredReminderCount)
            }
        } catch {
            if refreshGeneration == generation && !Task.isCancelled { status = .failed }
        }
    }

    public func requestPermission() async {
        do {
            status = try await client.requestAuthorization() ? .idle : .denied
        } catch {
            status = .failed
        }
    }

    private func nextGeneration(for eventID: UUID) -> UInt64 {
        let next = (generations[eventID] ?? 0) &+ 1
        generations[eventID] = next
        return next
    }

    private func invalidateActiveOperations() {
        for eventID in Array(operations.keys) {
            _ = nextGeneration(for: eventID)
            operations.removeValue(forKey: eventID)?.task.cancel()
        }
    }

    private func clearOperation(eventID: UUID, generation: UInt64) {
        guard operations[eventID]?.generation == generation else { return }
        operations.removeValue(forKey: eventID)
    }

    private func awaitOperation(
        _ task: Task<NotificationReconcileOutcome, Error>
    ) async throws -> NotificationReconcileOutcome {
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func logRefreshError(eventID: UUID?, error: any Error) {
        let eventToken = eventID?.uuidString.lowercased() ?? "orphan-cleanup"
        NSLog(
            "Notification refresh failed for %@ (%@)",
            eventToken,
            String(describing: type(of: error))
        )
    }
}
