public enum CollectionObservationDecision: Equatable {
    case observe
    case resetAccumulator

    public static func decide(
        legacyFlowPilotIsRunning: Bool,
        snapshotIsAvailable: Bool
    ) -> CollectionObservationDecision {
        legacyFlowPilotIsRunning || !snapshotIsAvailable ? .resetAccumulator : .observe
    }
}
