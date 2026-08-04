import Foundation

@MainActor
public final class NotificationUpdateCoordinator {
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

    public init(
        client: NotificationClient,
        planner: NotificationPlanner = NotificationPlanner(),
        betweenEvents: @escaping @MainActor () async -> Void = {}
    ) {
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
        deletedEventIDs.insert(eventID)
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
            logRefreshError(eventID: nil, error: error)
            return
        }

        let plans = planner.plans(
            for: events.filter { eventIDs.contains($0.id) },
            defaultHour: defaultHour,
            defaultMinute: defaultMinute,
            now: now,
            horizonDays: horizonDays,
            maximumPlans: maximumPlans,
            batchID: batchID
        )
        let plansByEvent = Dictionary(grouping: plans, by: \.eventID)

        for event in events {
            guard refreshGeneration == generation,
                  deletedEventIDs.contains(event.id) == false else {
                continue
            }
            let requests = (plansByEvent[event.id] ?? []).map { plan in
                ScheduledNotificationRequest(
                    identifier: plan.identifier,
                    eventID: plan.eventID,
                    title: plan.title,
                    body: plan.offsetDays == 0 ? "오늘 일정입니다." : "\(plan.offsetDays)일 전 알림입니다.",
                    fireDate: plan.fireDate
                )
            }
            do {
                _ = try await replace(eventID: event.id, requests: requests)
            } catch is CancellationError {
                if refreshGeneration != generation { return }
            } catch {
                logRefreshError(eventID: event.id, error: error)
            }

            await betweenEvents()
            if refreshGeneration != generation { return }
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
