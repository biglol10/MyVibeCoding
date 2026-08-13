public enum BrowserBridgeConnectionDecision: Equatable {
    case process
    case cancel
}

public struct BrowserBridgeListenerGeneration: Equatable {
    private var currentGeneration: UInt64 = 0

    public init() {}

    @discardableResult
    public mutating func activate() -> UInt64 {
        currentGeneration &+= 1
        return currentGeneration
    }

    public mutating func invalidate() {
        currentGeneration &+= 1
    }

    public func isCurrent(_ generation: UInt64) -> Bool {
        generation == currentGeneration
    }

    public func connectionDecision(for generation: UInt64) -> BrowserBridgeConnectionDecision {
        isCurrent(generation) ? .process : .cancel
    }
}
