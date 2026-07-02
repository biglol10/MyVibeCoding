import Foundation

public enum IdleStateEvaluator {
    public static let defaultThreshold: TimeInterval = 300

    public static func isIdle(
        secondsSinceLastInput: TimeInterval,
        threshold: TimeInterval = defaultThreshold
    ) -> Bool {
        guard secondsSinceLastInput.isFinite,
              threshold.isFinite,
              secondsSinceLastInput >= 0,
              threshold >= 0 else {
            return false
        }
        return secondsSinceLastInput >= threshold
    }
}
