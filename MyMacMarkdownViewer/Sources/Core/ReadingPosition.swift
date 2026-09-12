import Foundation

public struct ReadingPosition: Equatable, Sendable {
    public let anchor: Int
    public let head: Int
    public let scrollTop: Double

    public init(values: [String: Double], textLength: Int) {
        func offset(_ number: Double) -> Int {
            guard number.isFinite else { return 0 }
            return Int(min(Double(max(0, textLength)), max(0, number)))
        }
        anchor = offset(values["anchor"] ?? 0)
        head = offset(values["head"] ?? Double(anchor))
        let scroll = values["scrollTop"] ?? 0
        scrollTop = scroll.isFinite ? min(100_000_000, max(0, scroll)) : 0
    }
}
