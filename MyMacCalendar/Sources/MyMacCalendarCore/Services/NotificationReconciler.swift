import Foundation

public enum NotificationReconcileOutcome: Equatable, Sendable {
    case updated
    case notAuthorized
}

public enum NotificationIdentifier {
    public static func eventID(from identifier: String) -> UUID? {
        let prefix = "event-"
        guard identifier.hasPrefix(prefix) else { return nil }
        let remainder = identifier.dropFirst(prefix.count)
        guard remainder.count > 36 else { return nil }
        let uuidToken = String(remainder.prefix(36))
        guard remainder.dropFirst(36).first == "-" else { return nil }
        return UUID(uuidString: uuidToken)
    }

    public static func belongsToEvent(_ identifier: String, eventID: UUID) -> Bool {
        self.eventID(from: identifier) == eventID
    }
}

@MainActor
public final class NotificationReconciler {
    private let client: NotificationClient

    public init(client: NotificationClient) {
        self.client = client
    }

    public func reconcile(
        eventID: UUID,
        desired: [ScheduledNotificationRequest],
        isCurrent: @escaping @MainActor () -> Bool
    ) async throws -> NotificationReconcileOutcome {
        try validate(isCurrent)
        let validDesired = uniqueRequests(desired.filter { request in
            request.eventID == eventID && NotificationIdentifier.belongsToEvent(request.identifier, eventID: eventID)
        })
        if validDesired.isEmpty {
            return try await removeAll(eventID: eventID, isCurrent: isCurrent)
        }
        guard try await ensureAuthorization(requestIfNeeded: true, isCurrent: isCurrent) else {
            return .notAuthorized
        }

        try validate(isCurrent)
        let pending = try await client.pendingIdentifiers()
        try validate(isCurrent)

        let existing = Set(pending.filter { NotificationIdentifier.belongsToEvent($0, eventID: eventID) })
        let desiredIdentifiers = Set(validDesired.map(\.identifier))
        let stagingIdentifiers = validDesired.map(\.identifier)

        do {
            for request in validDesired {
                try validate(isCurrent)
                try await client.add(request)
                try validate(isCurrent)
            }

            let staleIdentifiers = existing.subtracting(desiredIdentifiers).sorted()
            try validate(isCurrent)
            if staleIdentifiers.isEmpty == false {
                await client.removePending(identifiers: staleIdentifiers)
                try validate(isCurrent)
            }
            return .updated
        } catch {
            if stagingIdentifiers.isEmpty == false {
                await client.removePending(identifiers: stagingIdentifiers)
            }
            throw error
        }
    }

    public func removeAll(
        eventID: UUID,
        isCurrent: @escaping @MainActor () -> Bool
    ) async throws -> NotificationReconcileOutcome {
        try validate(isCurrent)
        guard try await ensureAuthorization(requestIfNeeded: false, isCurrent: isCurrent) else {
            return .notAuthorized
        }
        try validate(isCurrent)
        let pending = try await client.pendingIdentifiers()
        try validate(isCurrent)
        let identifiers = pending
            .filter { NotificationIdentifier.belongsToEvent($0, eventID: eventID) }
            .sorted()
        if identifiers.isEmpty == false {
            await client.removePending(identifiers: identifiers)
            try validate(isCurrent)
        }
        return .updated
    }

    public func cleanupOrphans(
        validEventIDs: Set<UUID>,
        isCurrent: @escaping @MainActor () -> Bool
    ) async throws -> NotificationReconcileOutcome {
        try validate(isCurrent)
        guard try await ensureAuthorization(requestIfNeeded: false, isCurrent: isCurrent) else {
            return .notAuthorized
        }
        try validate(isCurrent)
        let pending = try await client.pendingIdentifiers()
        try validate(isCurrent)
        let orphanIdentifiers = pending.compactMap { identifier -> String? in
            guard let eventID = NotificationIdentifier.eventID(from: identifier),
                  validEventIDs.contains(eventID) == false else {
                return nil
            }
            return identifier
        }.sorted()
        if orphanIdentifiers.isEmpty == false {
            await client.removePending(identifiers: orphanIdentifiers)
            try validate(isCurrent)
        }
        return .updated
    }

    private func ensureAuthorization(
        requestIfNeeded: Bool,
        isCurrent: @escaping @MainActor () -> Bool
    ) async throws -> Bool {
        try validate(isCurrent)
        let state = try await client.authorizationState()
        try validate(isCurrent)
        switch state {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            guard requestIfNeeded else { return false }
            let granted = try await client.requestAuthorization()
            try validate(isCurrent)
            return granted
        }
    }

    private func validate(_ isCurrent: @MainActor () -> Bool) throws {
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
    }

    private func uniqueRequests(_ requests: [ScheduledNotificationRequest]) -> [ScheduledNotificationRequest] {
        var seen = Set<String>()
        return requests.filter { seen.insert($0.identifier).inserted }
    }
}
