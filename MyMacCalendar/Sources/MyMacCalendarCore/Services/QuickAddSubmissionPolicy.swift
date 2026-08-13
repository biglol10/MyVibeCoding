public enum QuickAddSubmissionDecision: Equatable {
    case unavailable
    case save(QuickAddResult)
    case confirmFallback(QuickAddResult)
}

public struct QuickAddSubmissionPolicy {
    public init() {}

    public func decision(for result: QuickAddResult?) -> QuickAddSubmissionDecision {
        guard let result else { return .unavailable }
        return result.needsConfirmation ? .confirmFallback(result) : .save(result)
    }
}
