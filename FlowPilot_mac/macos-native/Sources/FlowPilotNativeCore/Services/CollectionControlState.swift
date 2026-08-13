public struct CollectionControlState: Equatable {
    public private(set) var isManuallyPaused = false

    public init() {}

    @discardableResult
    public mutating func pause() -> Bool {
        guard !isManuallyPaused else { return false }
        isManuallyPaused = true
        return true
    }

    @discardableResult
    public mutating func resume() -> Bool {
        guard isManuallyPaused else { return false }
        isManuallyPaused = false
        return true
    }
}
