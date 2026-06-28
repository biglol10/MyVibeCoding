import Foundation

public struct WindowObservationSaveGate {
    private let minimumInterval: TimeInterval
    private var lastSavedAt: Date?

    public init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    public mutating func consumeIfDue(at observedAt: Date) -> Bool {
        guard let lastSavedAt else {
            self.lastSavedAt = observedAt
            return true
        }

        guard observedAt.timeIntervalSince(lastSavedAt) >= minimumInterval else {
            return false
        }

        self.lastSavedAt = observedAt
        return true
    }
}
